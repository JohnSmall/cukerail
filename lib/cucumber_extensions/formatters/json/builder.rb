#require 'cucumber/formatter/json'
module CucumberExtensions
  module Formatter
    # The formatter used for <tt>--format json_pretty</tt>
    class Json 
      class Builder
        def scenario_outline(scenario)
          puts 'in scenario outline'
          @test_case_hash = {
            id: create_id(scenario) + ';' + (@example_id.gsub(' ','').gsub(',',';')),
            keyword: scenario.keyword,
            name: scenario.name + ' ' + @example_id,
            description: scenario.description,
            line: @row.location.line,
            type: 'scenario'
          }
          tags = []
          tags += create_tags_array(scenario.tags) unless scenario.tags.empty?
          tags += @examples_table_tags if @examples_table_tags
          @test_case_hash[:tags] = tags unless tags.empty?
          comments = []
          comments += Formatter.create_comments_array(scenario.comments) unless scenario.comments.empty?
          comments += @examples_table_comments if @examples_table_comments
          comments += @row_comments if @row_comments
          @test_case_hash[:comments] =  comments unless comments.empty?
        end

        def examples_table(examples_table)
          puts 'in examples table'
          # the json file have traditionally used the header row as row 1,
          # wheras cucumber-ruby-core used the first example row as row 1.
          @example_id = @row.send(:data).map{|k,v| "#{k}=#{v}"}.join(", ")
          @examples_table_tags = create_tags_array(examples_table.tags) unless examples_table.tags.empty?
          @examples_table_comments = Formatter.create_comments_array(examples_table.comments) unless examples_table.comments.empty?
        end
       end
    end
  end
end

