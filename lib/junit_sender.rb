require_relative "cukerail/version"
require_relative "cukerail/testrail"
require 'awesome_print'
require 'nokogiri'
module Cukerail

  class JunitSender
    attr_reader :testrail_api_client,:results,:project_id,:suite_id,:testcases,:run_id
    def initialize(junit_file)
      if %w(BASE_URL USER PASSWORD).map{|e| ENV["TESTRAIL_#{e}"]}.any?{|e| e=='' || !e}
        raise 'You need to setup Testrail environment parameters see https://bbcworldwide.atlassian.net/wiki/display/BAR/Installing+and+Running+Cukerail' 
      end
      @project_id = ENV['PROJECT_ID']
      @suite_id = ENV['SUITE_ID']
      @testrail_api_client = TestRail::APIClient.new(ENV['TESTRAIL_BASE_URL'],ENV['TESTRAIL_USER'],ENV['TESTRAIL_PASSWORD'])
      @results   = Nokogiri::XML(File.read(junit_file))
      @testcases = Hash.new
      @run_id   = ENV['TESTRUN']
    end

    def load
      recurse_down(results)
    end

    def recurse_down(element,level=0,parent_id=nil)
      if element.name == 'document'
        element.children.each do |child|
          recurse_down(child)
        end
      end
      if element.name == 'testsuite'
        section_id = get_section_id(element,parent_id) 
      end
      element.children.select{|n| n.name=='testsuite'}.each do |testsuite|
        recurse_down(testsuite,level+1,(section_id || parent_id))
      end
      element.children.select{|n| n.name=='testcase'}.each do |testcase|
        case_id = get_testcase_id(testcase,(section_id || parent_id))
        report_result(case_id,testcase) if run_id
      end
    end

    #return nil if a section cannot be fouind or created
    def get_section_id(testsuite,parent_id=nil)
      # some elements don't have names
      return nil if  testsuite.attributes['name'].value.empty?
      section = sections.detect{|s| s['name'] == testsuite.attributes['name'].value}
      unless section
        section =  testrail_api_client.send_post("add_section/#{project_id}",{suite_id:suite_id,name:testsuite.attributes['name'].value,parent_id:parent_id})
        sections << section
      end
      section['id']
    end

    def sections
      @all_sections ||= get_sections
    end

    def get_sections
      sections = testrail_api_client.send_get("get_sections/#{project_id}&suite_id=#{suite_id}")
    end

    def get_testcase_id(testcase,section_id)
      unless testcases[section_id]
        testcases[section_id] = testrail_api_client.send_get("get_cases/#{project_id}&suite_id=#{suite_id}&section_id=#{section_id}")
      end
      unless testcases[section_id].detect{|tc| tc['title'] == testcase.attributes['name'].value}
        new_tc = testrail_api_client.send_post("add_case/#{section_id}",{title:testcase.attributes['name'].value,type_id:1})
        testcases[section_id] << new_tc
      end
      testcases[section_id].detect{|tc| tc['title'] == testcase.attributes['name'].value}['id']
    end

    def report_result(case_id,testcase)
      if testcase.children.any?{|c| c.name=='failure'}
        failure_text = testcase.children.select{|c| c.name=='failure'}.map{|c| c.text}.join("\n")
        result = {status_id: 5,comment: failure_text}
      else
        result = {status_id: 1,comment: 'passed'}
      end
      testrail_api_client.send_post("add_result_for_case/#{run_id}/#{case_id}",result)
    end

  end
end
