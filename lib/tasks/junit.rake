require_relative '../junit_sender'
desc "load Junit style xml results into test suite,FILE=results_file, PROJECT_ID=X, SUITE_ID=Y, optional SUB_SECTION=Z"
task :load_junit_results_to_test_suite do
 check_command_line_parameters_are_present
 junit = Cukerail::JunitSender.new(ENV['FILE'])
 junit.load
end

desc "load Junit style xml results into tesrun,FILE=results_file, PROJECT_ID=X, SUITE_ID=Y, optional SUB_SECTION=Z, TESTRUN=A"
task :load_junit_results_to_test_run do
 check_command_line_parameters_are_present
 raise 'TESTRUN is required' unless ENV['TESTRUN']
 junit = Cukerail::JunitSender.new(ENV['FILE'])
 junit.load
end
desc 'batch load files to a test run from a yaml file configuration YAML=file name'
task :batch_load_from_yaml do
  raise 'You must have YAML=file_name on the command line' unless ENV['YAML'] 
  raise 'PROJECT_ID is required' unless ENV['PROJECT_ID']
  raise 'SUITE_ID is required' unless ENV['SUITE_ID']
  yml = YAML.load_file(ENV['YAML'])
  yml.each_pair do | file_name,testrail_subsection_id |
    Cukerail::JunitSender.new(junit_file:file_name,
                             project_id: ENV['PROJECT_ID'],
                             suite_id: ENV['SUITE_ID'],
                             sub_section_id: testrail_subsection_id,
                             run_id: ENV['TESTRUN']).load
  end  
end

def check_command_line_parameters_are_present
 raise 'PROJECT_ID is required' unless ENV['PROJECT_ID']
 raise 'SUITE_ID is required' unless ENV['SUITE_ID']
 raise 'FILE is required' unless ENV['FILE']
end
