require_relative "cukerail/version"
require_relative "cukerail/testrail"
require 'json' unless JSON 
require 'awesome_print'
module Cukerail

  # Used to parase a json results file and send it to Testrail
  class JsonSender
    attr_reader :testrail_api_client,:results

    #initialize the sender class with the name of the file we will be reading from
    # @param json_file [string]
    def initialize(json_file)
      if %w(BASE_URL USER PASSWORD).map{|e| ENV["TESTRAIL_#{e}"]}.any?{|e| e=='' || !e}
        raise 'You need to setup Testrail environment parameters see https://bbcworldwide.atlassian.net/wiki/display/BAR/Installing+and+Running+Cukerail' 
      end
      @testrail_api_client = TestRail::APIClient.new(ENV['TESTRAIL_BASE_URL'],ENV['TESTRAIL_USER'],ENV['TESTRAIL_PASSWORD'])
      @results = JSON.parse(File.read(json_file)).select{|f| f['tags']}
    end

    # each feature file. Yield to a block
    def each_feature
      results.each do |feature|
        scenarios = feature['elements'].reject{|e| e['keyword']=='Background'}.select{|e| e['type'] == 'scenario'}
        project_id,suite_id,sub_section_id,background_steps = extract_top_level_data(feature)
        yield scenarios,project_id,suite_id,sub_section_id,background_steps
      end
    end

    # get the testcase id or create it if it doesn't exist
    # @param scenario [Scenario]
    # @param background_steps [Array]
    # @param project_id [integer]
    # @param suite_id [integer]
    # @param sub_section_id [integer]
    # @return [integer]
    def get_id(scenario,background_steps,project_id,suite_id,sub_section_id)
      title = get_name(scenario)
      scenario_level_sub_section = scenario['tags'].select{|j| j['name']=~/sub_section_\d+/}.last
      if scenario_level_sub_section
        sub_section_id_override = /sub_section_(\d+)/.match(scenario_level_sub_section['name'])[1]
      else
        sub_section_id_override=sub_section_id
      end
      found_case = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}&section_id=#{sub_section_id_override}").select{|c| c['title'] == title}.first
      if found_case
        result= found_case['id']
      else
        test_case = create_new_case(scenario,background_steps,project_id,suite_id,sub_section_id_override)
        result = test_case ? test_case['id'] : nil
      end
      return result
    end

    # extract data from the feature file
    # @param feature [Hash]
    #
    # @return [project_id,suite_id, sub_section_id, background_steps]
    def extract_top_level_data(feature)
      puts "feature file #{feature['uri']}"
      project_id = feature['tags'].select{|j| j['name']=~/project_\d+/}.map{|j| /project_(\d+)/.match(j['name'])[1].to_i}.first
      suite_id = feature['tags'].select{|j| j['name']=~/suite_\d+/}.map{|j| /suite_(\d+)/.match(j['name'])[1].to_i}.first
      sub_section_id = feature['tags'].select{|j| j['name']=~/sub_section_\d+/}.map{|j| /sub_section_(\d+)/.match(j['name'])[1].to_i}.first
      background=feature['elements'].select{|e| e['keyword']=='Background'}.first
      background_steps = background ? background['steps'].map{|s| s['keyword']+s['name']}.join("\n") : ''
      return project_id,suite_id,sub_section_id,background_steps
    end

    # get the name of the scenario, taking account of Scenario Outline Examples
    # @param scenario [Hash]
    # @return [string]
    def get_name(scenario)
      base_name = scenario['name']
      # We only extrapolate example data for scenario outlines
      is_scenario_outline = scenario['keyword'].downcase == 'scenario outline' ? true : false
      if is_scenario_outline
        # if we have scenario number then we assume this is just a JSON output without our id patch
        outline_number_str = scenario['id'].split(';').select{|e| e =~/^\d+$/}.first
        if outline_number_str
          outline_number = (outline_number_str.to_i) -1
        else
          # If we do not find an outline number, then we attempt to extrapolate the example data from the
          # id if there is any and append to the base name. note: _ before variable means it is not going
          # to be used
          _feature, _scenario, example_data = scenario['id'].split(';')
          unless example_data.nil? && example_data.strip.empty?
            base_name = if ENV['OLD_STYLE_OUTLINE_NAMES']
                          "#{base_name} :: #{example_data}"
                        else
                          "#{base_name} #{example_data}"
                        end
          end
        end
      end
      tags = [scenario['tags']].flatten.compact
      requirement = tags.select{|t| t['name'] =~/@req/}.map{|t| /@req_(\w+)/.match(t['name'])[1]}.first unless tags.empty?
      [requirement, base_name, outline_number].join(' ').strip
    end

    # create a new test case in Testrail
    # @param scenario [Hash]
    # @param background_steps [Array]
    # @param project_id [Integer]
    # @param suite_id [Integer]
    # @param sub_section_id [Integer]
    def create_new_case(scenario,background_steps,project_id,suite_id,sub_section_id)
      data = prepare_data(scenario,background_steps)
      testrail_api_client.send_post("add_case/#{sub_section_id || suite_id}", data)
    rescue StandardError => e
      puts "#{e.message} in #{get_name(scenario)}"
      return nil
    end


    # send the steps in the scenario to Testrail
    # @param scenario [Hash]
    # @param background_steps [Array]
    # @param testcase_id [Integer]
    def send_steps(scenario,background_steps,testcase_id)
      data = prepare_data(scenario,background_steps)
      testrail_api_client.send_post("update_case/#{testcase_id}",data)
    rescue StandardError => e
      puts "#{e.message} in #{get_name(scenario)}"
      return nil
    end

    # bundle up a data hash ready to send to Testrail for the testcase
    # @param scenario [Hash]
    # @param background_steps [Array]
    # @return [Hash]
    def prepare_data(scenario,background_steps)
      steps = background_steps + "\n" + scenario['steps'].map{|s| s['keyword']+s['name']}.join("\n")
      type_ids = [1]
      type_ids << 7  if scenario['tags'].any?{|tag| tag['name'] =~/manual/}
      type_ids << 13 if scenario['tags'].any?{|tag| tag['name'] =~/on_hold/}
      #get the highest precedence type found in the tags. E.g. if it's @on_hold and @manual it selects 13 for on hold
      type_id = ([13,7,1] & type_ids).first

      data = {'title'=>get_name(scenario),
              'type_id'=>type_id,
              'custom_steps'=>steps,
              'refs'=>refs(scenario)
      }
    end

    # extract the defect tags from the scenario
    # @param scenario [Hash]
    # @return [Array]
    def defects(scenario)
      if scenario['tags']
        tags = [scenario['tags']].flatten.compact
        tags.select{|tag| tag['name'] =~/(?:jira|defect)_/}.map{|ticket| /(?:jira|defect)_(\w+-\d+)$/.match(ticket['name'])[1]}.uniq.join(",")
      end
    end
 
    # extract reference tags from the scenario
    # @param scenario [Hash]
    # @return [Array]
    def refs(scenario)
      if scenario['tags']
        tags = [scenario['tags']].flatten.compact
        tags.select{|tag| tag['name'] =~/(?:jira|ref)_/}.map{|ticket| /(?:jira|ref)_(\w+-\d+)$/.match(ticket['name'])[1]}.uniq.join(",")
      end
    end
    
    # Send the result to Testrail
    # @param scenario [Hash]
    # @param id [Integer]
    # @param run_id [Integer]
    def send_result(scenario,id,run_id)
      error_line = scenario['steps'].select{|s| s['result']['status'] != 'passed'}.first 
      if error_line
        #puts error_line['result']
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
      tries = 3
      begin
        testrail_api_client.send_post("add_result_for_case/#{run_id}/#{id}",report_on_result)
      rescue => e
        if e.message =~ /No \(active\) test found for the run\/case combination/
          tries -= 1
          add_case_to_test_run(id,run_id)
          if tries > 0
            retry
          else
            puts "#{e.message} testrun=#{run_id} test case id=#{id}"
          end
        else
          puts "#{e.message} testrun=#{run_id} test case id=#{id}"
        end
      end
    end

    # get the Testrail run from the Testrail run id
    # @param run_id [Integer]
    # @return [json]
    def get_run(run_id)
      testrail_api_client.send_get("get_run/#{run_id}")
    end

    # get all the tests in a ren from Testrail
    # @param run_id [integer]
    # @return [json]
    def get_tests_in_a_run(run_id)
      testrail_api_client.send_get("get_tests/#{run_id}")
    end

    # update a Testrail test run
    # @param run_id [integer]
    # @param case_ids [Array]
    def update_run(run_id,case_ids)
      run = get_run(run_id)
      begin
        if run['plan_id']
          update_plan(run['plan_id'],run_id,case_ids)
        else
          testrail_api_client.send_post("update_run/#{run_id}",case_ids)
        end
      rescue => e
        puts "#{e.message} testrun=#{run_id} test case ids=#{case_ids}"
      end
    end

    #update a Testrail test plan - these have to be treadted differently to plain test runs
    # @param plan_id [integer]
    # @param run_id [integer]
    # @param case_ids [Array]
    def update_plan(plan_id,run_id,case_ids)
      test_plan = testrail_api_client.send_get("get_plan/#{plan_id}")
      entry_id = test_plan['entries'].select{|e| e['runs'].any?{|r| r['id']==run_id}}.first['id']
      testrail_api_client.send_post("update_plan_entry/#{plan_id}/#{entry_id}",case_ids)
    end

    # remove a case from a Testrail test run
    # @param testcase [Hash]
    # @param run_id [integer]
    def remove_case_from_test_run(testcase,run_id)
      testcase_id = get_id(testcase)
      run = get_run(run_id)
      unless run['include_all']
        case_ids = get_tests_in_a_run(run_id).map{|h| h['case_id']} - [testcase_id]
        update_run(run_id,{'case_ids'=>case_ids})
      end
    end

    # add a new case to a Testrail test run
    # @param testcase_id [integer]
    # @param run_id [integer]
    def add_case_to_test_run(testcase_id,run_id)
      run = get_run(run_id)
      unless run['include_all']
        puts "add testcase #{testcase_id} to run #{run_id}"
        case_ids = get_tests_in_a_run(run_id).map{|h| h['case_id']} + [testcase_id]
        update_run(run_id,{'case_ids'=>case_ids})
      end
    end

    # remove a block of test cases from a testrun
    # @param testcases [Array]
    # @param run_id [integer]
    def remove_all_except_these_cases_from_testrun(testcases,run_id)
      run = get_run(run_id)
      unless run['include_all']
        case_ids = get_tests_in_a_run(run_id).map{|h| h['case_id']} & testcases
        update_run(run_id,{'case_ids'=>case_ids})
      end
    end

    # remove all except an array of cases from a test suite
    # @param testcases [Array]
    # @param project_id [integer]
    # @param suite_id [integer]
    def remove_all_except_these_cases_from_suite(testcases,project_id,suite_id)
      puts '=== testcases === '
      puts testcases
      # get a list of automated tests, ignore manual or on hold tests
      existing_cases = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}").select{|t| t['type_id']==1}.map{|m| m['id']}
      puts '===== existing_cases === '
      puts existing_cases
      (existing_cases - testcases).each do |case_to_remove|
        puts "case_to_remove #{case_to_remove}"
        testrail_api_client.send_post("delete_case/#{case_to_remove}",nil)
      end
    end
  end
end
