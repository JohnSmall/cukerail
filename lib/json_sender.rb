require_relative "cukerail/version"
require_relative "cukerail/testrail"
require 'json' unless JSON 
module Cukerail
  class JsonSender
    attr_reader :testrail_api_client,:results
    def initialize(json_file)
      if %w(BASE_URL USER PASSWORD).map{|e| ENV["TESTRAIL_#{e}"]}.any?{|e| e=='' || !e}
        raise 'You need to setup Testrail environment parameters see https://bbcworldwide.atlassian.net/wiki/display/BAR/Installing+and+Running+Cukerail' 
      end
      @testrail_api_client = TestRail::APIClient.new(ENV['TESTRAIL_BASE_URL'],ENV['TESTRAIL_USER'],ENV['TESTRAIL_PASSWORD'])
      @results = JSON.parse(File.read(json_file)).select{|f| f['tags']}
    end

    def each_feature
      results.each do |feature|
        scenarios = feature['elements'].reject{|e| e['keyword']=='Background'}.select{|e| e['type'] == 'scenario'}
        project_id,suite_id,sub_section_id,background_steps = extract_top_level_data(feature)
        yield scenarios,project_id,suite_id,sub_section_id,background_steps
      end
    end


    def get_id(scenario,background_steps,project_id,suite_id,sub_section_id)
      title = get_name(scenario)
      found_case = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}").select{|c| c['title'] == title}.first
      if found_case
        result= found_case['id']
      else
        result = create_new_case(scenario,background_steps,project_id,suite_id,sub_section_id)['id']
      end
      return result
    end

    def extract_top_level_data(feature)
      puts "feature file #{feature['uri']}"
      project_id = feature['tags'].select{|j| j['name']=~/project_\d+/}.map{|j| /project_(\d+)/.match(j['name'])[1].to_i}.first
      suite_id = feature['tags'].select{|j| j['name']=~/suite_\d+/}.map{|j| /suite_(\d+)/.match(j['name'])[1].to_i}.first
      sub_section_id = feature['tags'].select{|j| j['name']=~/sub_section_\d+/}.map{|j| /sub_section_(\d+)/.match(j['name'])[1].to_i}.first
      background=feature['elements'].select{|e| e['keyword']=='Background'}.first
      background_steps = background ? background['steps'].map{|s| s['keyword']+s['name']}.join("\n") : ''
      return project_id,suite_id,sub_section_id,background_steps
    end

    def get_name(scenario)
      base_name = scenario['name']
      outline_number_str = scenario['id'].split(';').select{|e| e =~/^\d+$/}.first
      if outline_number_str
        outline_number = (outline_number_str.to_i) -1
      end
      tags= [scenario['tags']].flatten.compact
      requirement = tags.select{|t| t['name'] =~/@req/}.map{|t| /@req_(\w+)/.match(t['name'])[1]}.first unless tags.empty?
      [requirement, base_name, outline_number].join(' ').strip
    end

    def create_new_case(scenario,background_steps,project_id,suite_id,sub_section_id)
      data = prepare_data(scenario,background_steps)
      testrail_api_client.send_post("add_case/#{sub_section_id || suite_id}", data)
    end

    def send_steps(scenario,background_steps,testcase_id)
      data = prepare_data(scenario,background_steps)
      testrail_api_client.send_post("update_case/#{testcase_id}",data)
    end

    def prepare_data(scenario,background_steps)
      steps = background_steps + "\n" + scenario['steps'].map{|s| s['keyword']+s['name']}.join("\n")
      is_manual = scenario['tags'].any?{|tag| tag['name'] =~/manual/} if scenario['tags']
      data = {'title'=>get_name(scenario),
              'type_id'=>(is_manual ? 7 : 1 ),
              'custom_steps'=>steps,
              'refs'=>defects(scenario)
      }
    end

    def defects(scenario)
      if scenario['tags']
        scenario['tags'].select{|t| t['name'] =~/@jira_/}.map{|t| /jira_(\w+-\w+)/.match(t['name'])}.join(' ')
      end
    end

    def send_result(scenario,id,testrun)
      error_line = scenario['steps'].select{|s| s['result']['status'] != 'passed'}.first 
      if error_line
        puts error_line['result']
        testrail_status = case error_line['result']['status']
                          when 'failed'
                            {id:5,comment: 'failed'}
                          when 'undefined'
                            {id:7,comment: 'undefined step'}
                          when  'pending'
                            {id:6,comment: 'pending step'}
                          when  'skipped'
                            {id:5,comment: 'failed in before hook'}
                          end
        error_result = error_line['error_message']
        failure_message = <<-FAILURE
        Error message: #{testrail_status[:comment]} #{error_result}
        Step: #{error_line['keyword']} #{error_line['name']}
        Location: #{error_line['match']['location']}
        FAILURE
      else
        testrail_status = {id:1,comment: 'passed'}
        failure_message = nil
      end
      report_on_result =  {status_id:testrail_status[:id],comment:failure_message,defects:defects(scenario)}
      begin
        testrail_api_client.send_post("add_result_for_case/#{testrun}/#{id}",report_on_result)
      rescue => e
        if e.message =~ /No \(active\) test found for the run\/case combination/
          add_case_to_test_run(id,testrun)
          retry
        else
          puts "#{e.message} testrun=#{testrun} test case id=#{id}"
        end
      end
    end

    def get_run(run_id)
      testrail_api_client.send_get("get_run/#{run_id}")
    end

    def get_tests_in_a_run(run_id)
      testrail_api_client.send_get("get_tests/#{run_id}")
    end

    def update_run(testrun,case_ids)
      begin
        testrail_api_client.send_post("update_run/#{testrun}",case_ids)
      rescue => e
        puts "#{e.message} testrun=#{testrun} test case ids=#{case_ids}"
      end
    end

    def remove_case_from_test_run(testcase,testrun)
      testcase_id = get_id(testcase)
      run = get_run(testrun)
      unless run['include_all']
        case_ids = get_tests_in_a_run(testrun).map{|h| h['case_id']} - [testcase_id]
        update_run(testrun,{'case_ids'=>case_ids})
      end
    end

    def add_case_to_test_run(testcase_id,testrun)
      run = get_run(testrun)
      unless run['include_all']
        case_ids = get_tests_in_a_run(testrun).map{|h| h['case_id']} + [testcase_id]
        update_run(testrun,{'case_ids'=>case_ids})
      end
    end

    def remove_all_except_these_cases_from_testrun(testcases,testrun)
      run = get_run(testrun)
      unless run['include_all']
        case_ids = get_tests_in_a_run(testrun).map{|h| h['case_id']} & testcases
        update_run(testrun,{'case_ids'=>case_ids})
      end
    end

    def remove_all_except_these_cases_from_suite(testcases,project_id,suite_id)
      puts '=== testcases === '
      puts testcases
      existing_cases = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}").map{|m| m['id']}
      puts '===== existing_cases === '
      puts existing_cases
      (existing_cases - testcases).each do |case_to_remove|
        puts "case_to_remove #{case_to_remove}"
        testrail_api_client.send_post("delete_case/#{case_to_remove}",nil)
      end
    end
  end
end
