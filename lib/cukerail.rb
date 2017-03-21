require "cukerail/version"
require "cukerail/testrail"
# require_relative "cucumber_extensions/formatters/json/builder"
# puts 'load extensions'
# puts (Cucumber::Formatter.name)
# Cucumber::Formatter::Json::Builder.include CucumberExtensions::Formatter::Json::Builder
module Cukerail
  # Cukeral::Sender
  # This class had the methods that hook into the Cucumber callbacks
  # Read about Cucumber custom formatters here https://github.com/cucumber/cucumber/wiki/Custom-Formatters
  class Sender
    attr_reader :testrail_api_client,:failed_step

    # initialize the formatter
    # The input variables runtim, io and options are required by Cucumber, but they give no explanation of what
    # the are and we don't use them
    # 
    # Ignoring those variables, we set up an instance of the Testrail::APIClient to be used while we respond to events from Cucumber
    def initialize(runtime, io, options)
      if %w(BASE_URL USER PASSWORD).map{|e| ENV["TESTRAIL_#{e}"]}.any?{|e| e=='' || !e}
        raise 'You need to setup Testrail environment parameters see https://bbcworldwide.atlassian.net/wiki/display/BAR/Installing+and+Running+Cukerail' 
      end
      @testrail_api_client = TestRail::APIClient.new(ENV['TESTRAIL_BASE_URL'],ENV['TESTRAIL_USER'],ENV['TESTRAIL_PASSWORD'],ENV['TESTRAIL_PROXY_URL'],ENV['TESTRAIL_PROXY_PORT'])
    end

    # after_test_case
    # @param test_case [test_case]
    # @param result [result]
    #
    # @return nil
    #
    def after_test_case(test_case,result)
      #guard clause
      return false unless test_case.tags.any?{|tag| tag.name =~/project/} && test_case.tags.any?{|tag| tag.name=~/suite/} 
      feature = test_case.feature
      #      ap feature.methods - Object.methods
      #      ap feature.tags
      @id = get_id(test_case)
      raise 'No id found' unless @id
      send_steps(test_case,@id)
      if ENV['UPDATE_SOURCE'] && !test_case.source.any?{|h| h.is_a?(Cucumber::Core::Ast::ScenarioOutline)}
        update_source_file(test_case,@id)
      end
      if ENV['TESTRUN']
        send_result(test_case,result,@id,ENV['TESTRUN'].to_i) 
      end
    rescue StandardError => e
      puts "#{e.message} in #{extract_title(test_case)}"
    end

    # adds a tag_name to the list of scenario tags
    #
    # @param tag_name string
    #
    # @return all the scenario tags [Array]
    def tag_name(tag_name)
      @scenario_tags << tag_name
    end
    # used to accumulate the steps while the scenario is running so we have them all when we end the scenario
    #
     def step_name(keyword, step_match, status, source_indent, background, file_colon_line)
       step_name = step_match.format_args(lambda{|param| "*#{param}*"})
       @test_steps << "#{keyword}#{step_name}"
     end

     # unless the test passed, save the failed step and the result
     #
     # @param step [step]
     # @param result [string]
    def after_test_step(step,result)
      unless result.passed?
        # only the first non-passed step
        failed_step[:step]   ||= step
        failed_step[:result] ||= result
      end
    end
 
    # set up arrays and hashes to capture test steps, stcanior tags and failed step information before running the test
    def before_test_case(*args)
      @test_steps =[]
      @scenario_tags = []
      @failed_step = {}
    end

    # get the Terrail id for the test case
    #
    # @param test_case [test_case]
    #
    # @return [integer]
    #
    def get_id(test_case)
      #      ap test_case.methods - Object.methods
      tagged_id = test_case.tags.detect{|tag| tag.name =~/testcase/}
      if tagged_id
        result = /testcase_(\d+)/.match(tagged_id.name)[1]
      else
        tags = test_case.tags
        project_id = /\d+/.match(tags.select{|tag| tag.name =~/project/}.last.name)[0] 
        suite_id = /\d+/.match(tags.select{|tag| tag.name =~/suite/}.last.name)[0] 
        section_id = /\d+/.match(tags.select{|tag| tag.name =~/sub_section/}.last.name)[0]
        title = extract_title(test_case)
        found_case = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}&section_id=#{section_id}").select{|c| c['title'] == title}.first
        if found_case
          result= found_case['id']
        else
          result = create_new_case(project_id,suite_id,section_id,test_case)['id']
        end
      end
      return result
    end

    # if required, then add the Testrail reference to the source file. This will be a tag @testcase_x
    def update_source_file(scenario, external_reference)
      #this could be done on one line with sed. But the format is different on Mac OS and GNU Linux version and it definitely won't work on a Windows machine
      # byebug
      path = scenario.location.file
      # ap path
      lines = IO.readlines(path)
      lines[scenario.location.line-2].gsub!(/ @testcase_\d*/," @testcase_#{external_reference}") 
      lines[scenario.location.line-2].gsub!(/\n/," @testcase_#{external_reference}") unless lines[scenario.location.line-2] =~ /testcase/ 
      temp_file = Tempfile.new('foo')
      begin
        File.open(path, 'r') do |file|
          lines.each do |line|
            # puts line
            temp_file.puts line
          end
        end
        temp_file.close
        FileUtils.mv(temp_file.path, path)
      ensure
        temp_file.close
        temp_file.unlink
      end
    end
   
    # send the steps to the Testrail testcase. This overwrites anything already there
    # @param test_case [test_case]
    # @param id [integer]
    def send_steps(test_case,id)
      testrail_api_client.send_post("update_case/#{id}",test_case_data(test_case))
    end

    # create a new Testrail testcase
    #
    # @param project_id [integer]
    # @param suite_id [integer]
    # @param sub_section_id [integer]
    # @param test_case [Testcase]
    #
    def create_new_case(project_id,suite_id,sub_section_id,test_case)
      testrail_api_client.send_post("add_case/#{sub_section_id || suite_id}",test_case_data(test_case))
    end
    
    # send the result to Testrail
    # @param test_Case [test_case]
    # @param result [test_result]
    # @param id [integer]
    # @param testrun [integer]
    def send_result(test_case,result,id,testrun)
      testrail_status = case 
                        when result.passed?
                          {id:1,comment: 'passed'}
                        when result.failed?
                          {id:5,comment: 'failed'}
                        when result.undefined?
                          {id:7,comment: 'undefined step'}
                        when result.pending?
                          {id:6,comment: 'pending step'}
                        end
      unless result.passed?
        # the before step can fail. So we have to check
        if @failed_step[:step].source.last.is_a?(Cucumber::Hooks::BeforeHook)
          failed_step = 'failed in the before hook'
          location = 'before hook'
        elsif @failed_step[:step].source.last.is_a?(Cucumber::Hooks::AfterHook)
          failed_step = 'failed in the after hook'
          location = 'after hook'
        else
          failed_step = "#{@failed_step[:step].source.last.keyword}#{@failed_step[:step].source.last.name}"
          location=@failed_step[:step].source.last.file_colon_line
        end
        failure_message = <<-FAILURE
        Error message: #{testrail_status[:comment]} #{result.exception.message}
        Step: #{failed_step}
        Location: #{location}
        FAILURE
      else
        failure_message = nil
      end
      #only send defects if the test is not passed
      report_on_result =  {status_id:testrail_status[:id],comment:failure_message,defects:testrail_status[:id]==1 ? '' : defects(test_case)}
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
    
    # extract the title of the scenario, taking account of Scenario Outline Exampole tables
    # @param test_case [test_case]
    # @return [string]
    def extract_title(test_case)
      requirements_tags = all_tags(test_case).select{|tag| tag.name =~ /req_\w+/}.map{|tag| /req_(\w+)/.match(tag.name)[1]}.join(', ')
      if test_case.source.last.is_a?(Cucumber::Core::Ast::ExamplesTable::Row)
        title  = test_case.source.select{|s| s.is_a?(Cucumber::Core::Ast::ScenarioOutline)}.first.name
        if ENV['OLD_STYLE_OUTLINE_NAMES'] 
          title += ' :: ' + test_case.source.last.send(:data).map{|key,value| "#{key}='#{value}'"}.join(', ')
        else
          title += " " + test_case.source.last.send(:data).map{|key,value| "#{key}=#{value}"}.join(', ')
        end
      else
        title = test_case.source.last.name
      end
      [requirements_tags,title].compact.join(' ').strip
    end

    # get the Testrail run for a Testrail run id
    # @param run_id [integer]
    # @return [json]
    def get_run(run_id)
      testrail_api_client.send_get("get_run/#{run_id}")
    end

    # Gets all tests in a run so we can add new tests if required
    # @param run_id [integer]
    # @return [json]
    def get_tests_in_a_run(run_id)
      testrail_api_client.send_get("get_tests/#{run_id}")
    end

    # all the tags, including the feature level tags
    # @param test_case [test_case]
    def all_tags(test_case)
      test_case.tags + test_case.feature.tags
    end

    # Jira defect tags for a test case
    # @param test_case [test_case]
    # @return [Array]
    def defects(test_case)
      all_tags(test_case).select{|tag| tag.name =~/(?:jira|defect)_/}.map{|ticket| /(?:jira|defect)_(\w+-\d+)$/.match(ticket.name)[1]}.uniq.join(",")
    end

    # Jira reference tags for a test case
    # @param test_case [test_case]
    # @return [Array]
    def refs(test_case)
      all_tags(test_case).select{|tag| tag.name =~/(?:jira|ref)_/}.map{|ticket| /(?:jira|ref)_(\w+-\d+)$/.match(ticket.name)[1]}.uniq.join(",")
    end

    # get the Testrail type id for the test case.
    # This will be different for different users depending on your Testrail configuration
    #
    # Therefore there's a default type id 1 for automated
    #
    # the you can add @manual (type_id 7)  and @onhold (type_id 13) and it returns the highest number
    # because we're set up like that. 
    #
    # If you have difference mappings then you can provide a mapping file 
    # in ENV['TYPE_MAPPING_FILE'], which should be just an array of your tag names
    # (remember you can't have spaces in the tag names)
    #
    # if you then add tags @type_my_tag_name, it will find the index of 'my_tag_name' in the file and add that to an internal array
    # it then take the highest number in the array as the type_id
    #
    # @param test_case [test_case]
    #
    # @return integer
    def type_id(test_case)
      type_ids = [1]
      if ENV['TYPE_MAPPING_FILE'] && File.exists?(ENV['TYPE_MAPPING_FILE'])
        type_mappings = YAML.load(File.read(ENV['TYPE_MAPPING_FILE']))
        type_ids += test_case.tags.select{|tag| tag.name =~/type/}.map{|t| type_mappings.index_of(/type_(\S+)/.match(t.name)[1])+1}
      else
        type_ids << 7  if test_case.tags.any?{|tag| tag.name =~/manual/}
        type_ids << 13 if test_case.tags.any?{|tag| tag.name =~/on_hold/}
      end
      type_ids.sort.last
    end


    # extracts data from a testcase to send it to Testrail
    #
    # @param test_case [Scenario]
    #
    # @return [hash]
    def test_case_data(test_case)
      steps_as_string = test_case.test_steps.map{|step| step.source.last}
      .select{|step| step.is_a?(Cucumber::Core::Ast::Step)}
      .reject{|step| step.is_a?(Cucumber::Hooks::BeforeHook)}.map do | g_step |
        str = g_step.send(:keyword)+g_step.send(:name)
        str += g_step.multiline_arg.raw.map{|l|"\n| #{l.join(' | ')} |"}.join if g_step.multiline_arg.data_table?
        str
      end.join("\n")
      {'title'=>extract_title(test_case),
       'type_id'=>type_id(test_case),
       'custom_steps'=>steps_as_string,
       'refs'=>refs(test_case)
      }
    end

    # update a Testrail testrun by adding new tests into it if required
    # @param run_id [integer]
    # @param case_ids[Array]
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

    # update a Testrail test plan with new case_ids
    # @param plan_id
    # @param run_id
    # @param case_ids
    def update_plan(plan_id,run_id,case_ids)
      test_plan = testrail_api_client.send_get("get_plan/#{plan_id}")
      entry_id = test_plan['entries'].detect{|e| e['runs'].any?{|r| r['id']==run_id}}['id']
      testrail_api_client.send_post("update_plan_entry/#{plan_id}/#{entry_id}",case_ids)
    end

    # remove a case from a test run/ This is only used inside a rake task where it has all the ides for a run so it can see which ones it has to remove
    # @param testcase [test_case]
    # @param run_id [integer]
    def remove_case_from_test_run(testcase,run_id)
      testcase_id = get_id(testcase)
      run = get_run(run_id)
      unless run['include_all']
        case_ids = get_tests_in_a_run(run_id).map{|h| h['case_id']} - [testcase_id]
        update_run(run_id,{'case_ids'=>case_ids})
      end
    end

    # add a case from a test run/ 
    # @param testcase_id [integer]
    # @param run_id [integer]
    def add_case_to_test_run(testcase_id,run_id)
      run = get_run(run_id)
      unless run['include_all']
        case_ids = get_tests_in_a_run(run_id).map{|h| h['case_id']} + [testcase_id]
        update_run(run_id,{'case_ids'=>case_ids})
      end
    end

  end

end
