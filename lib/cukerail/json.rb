# Cukerail module to create our own json formatter which does the scenario outlines and examples as we need them
# The standard json formater just list the scenarion outline examples as numbers, which is no good for identifying
# testcases by name and assigning ids to them in Testrail
module Cukerail
    require 'cucumber/formatter/json'
    # Match the class/module structure in the Cucumber json formatter so we can re-open the class and override the examples table method
    class Json < Cucumber::Formatter::Json
      # match the class/module structure to override the examples table method in the json formatter
      class Cucumber::Formatter::Json::Builder
        # get the scenaio names using the Scenario Outline and the parameters on the example table
        # @param examples_table [examples_table]
        def examples_table(examples_table)
          # puts 'in examples table'
          # We want the row data to be used in making the full scenario name
          if ENV['OLD_STYLE_OUTLINE_NAMES']
            @example_id = @row.send(:data).map{|k,v| "#{k}='#{v}'"}.join(", ")
          else
            @example_id = @row.send(:data).map{|k,v| "#{k}=#{v}"}.join(", ")
          end
          @examples_table_tags = create_tags_array(examples_table.tags) unless examples_table.tags.empty?
          @examples_table_comments = ::Cucumber::Formatter.create_comments_array(examples_table.comments) unless examples_table.comments.empty?
        end
       end
    end
end
