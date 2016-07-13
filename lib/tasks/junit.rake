require_relative '../junit_sender'
desc "load Junit style xml results into test suite,FILE=results_file, PROJECT_ID=X, SUITE_ID=Y, optional SUB_SECTION=Z"
task :load_junit_results_to_test_suite do
 junit = Cukerail::JunitSender.new(ENV['FILE'])
 junit.load
 # junit.get_sections
end

desc "load Junit style xml results into test run,FILE=results_file, TESTRUN=R, PROJECT_ID=X, SUITE_ID=Y, optional SUB_SECTION=Z"
task :load_junit_results_to_test_run do
end
