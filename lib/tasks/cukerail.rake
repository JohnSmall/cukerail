require_relative '../json_sender'
desc 'load a json results file into a test suite'
task :load_to_suite do
  raise 'You must have JSON=filename on the command line' unless ENV['JSON']
  json_sender =Cukerail::JsonSender.new(ENV['JSON'])
  features = json_sender.results
  #only work with feature files that have tags set up
  features.select{|f| f['tags']}.each do | feature |
    # project_id = feature['tags'].select{|j| j['name']=~/project_\d+/}.map{|j| /project_(\d+)/.match(j['name'])[1].to_i}.first
    # suite_id = feature['tags'].select{|j| j['name']=~/suite_\d+/}.map{|j| /suite_(\d+)/.match(j['name'])[1].to_i}.first
    # sub_section_id = feature['tags'].select{|j| j['name']=~/sub_section_\d+/}.map{|j| /sub_section_(\d+)/.match(j['name'])[1].to_i}.first
    # background=feature['elements'].select{|e| e['keyword']=='Background'}.first
    # background_steps = background['steps'].map{|s| s['keyword']+s['name']}.join("\n")
    project_id,suite_id,sub_section_id,background_steps = json_sender.extract_top_level_data(feature)
    feature['elements'].reject{|e| e['keyword']=='Background'}.select{|e| e['type'] == 'scenario'}.each do | scenario |
      testcase_id = json_sender.get_id(scenario,background_steps,project_id,suite_id,sub_section_id) if scenario['type'] == 'scenario'
      puts "testcase_id = #{testcase_id}"
      json_sender.send_steps(scenario,background_steps,testcase_id)
    end
  end
end

desc 'load a json results file into a test run'
task :load_to_test_run do
  raise 'You must have TESTRUN=testrun_number on the command line' unless ENV['TESTRUN']
  json_sender =Cukerail::JsonSender.new(ENV['JSON'])
  #only work with feature files that have tags set up
  json_sender.each_feature do | scenarios,project_id,suite_id,sub_section_id,background_steps |
    scenarios.each do | scenario |
    testcase_id = json_sender.get_id(scenario,background_steps,project_id,suite_id,sub_section_id)
    puts "scenario_id #{scenario['id']} testcase_id = #{testcase_id}"
    json_sender.send_steps(scenario,background_steps,testcase_id)
    json_sender.send_result(scenario,testcase_id,ENV['TESTRUN'])
  end
  end
end

desc "remove cases from a test run that are aren't in the json results"
task :remove_from_test_run do
  raise 'You must have TESTRUN=testrun_number on the command line' unless ENV['TESTRUN']
  raise 'You must have JSON=filename on the command line' unless ENV['JSON']
  json_sender =Cukerail::JsonSender.new(ENV['JSON'])
  testcase_ids = []
  json_sender.each_feature do | scenarios,project_id,suite_id,sub_section_id,background_steps |
    scenarios.each do | scenario |
    testcase_ids << json_sender.get_id(scenario,background_steps,project_id,suite_id,sub_section_id)
  end  
  end  
  json_sender.remove_all_except_these_cases_from_testrun(testcase_ids,ENV['TESTRUN'])
end

desc "match test run cases to json results file"
task match_to_test_run: [:remove_from_test_run,:load_to_test_run] do 
end

desc "remove cases from a test suite that aren't in the json results"
task :remove_from_test_suite do
  raise 'You must have JSON=filename on the command line' unless ENV['JSON']
  json_sender =Cukerail::JsonSender.new(ENV['JSON'])
  testcase_ids = []
  ex_project_id = 0
  ex_suite_id = 0
  json_sender.each_feature do | scenarios,project_id,suite_id,sub_section_id,background_steps |
    ex_project_id = project_id
    ex_suite_id = suite_id
    scenarios.each do | scenario |
      testcase_ids << json_sender.get_id(scenario,background_steps,project_id,suite_id,sub_section_id)
    end  
  end  
  json_sender.remove_all_except_these_cases_from_suite(testcase_ids,ex_project_id,ex_suite_id)
end
