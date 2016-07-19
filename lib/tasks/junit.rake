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

def check_command_line_parameters_are_present
 raise 'PROJECT_ID is required' unless ENV['PROJECT_ID']
 raise 'SUITE_ID is required' unless ENV['SUITE_ID']
 raise 'FILE is required' unless ENV['FILE']
end
