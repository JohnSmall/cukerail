module Cukerail
    require 'cucumber/formatter/json'
    class Json < Cucumber::Formatter::Json
      class Cucumber::Formatter::Json::Builder
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
          # We want the row data to be used in making the full scenario name
          @example_id = @row.send(:data).map{|k,v| "#{k}=#{v}"}.join(", ")
          @examples_table_tags = create_tags_array(examples_table.tags) unless examples_table.tags.empty?
          @examples_table_comments = Formatter.create_comments_array(examples_table.comments) unless examples_table.comments.empty?
        end
       end
    end
end
