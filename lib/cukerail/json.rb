module Cukerail
    require 'cucumber/formatter/json'
    class Json < Cucumber::Formatter::Json
      class Cucumber::Formatter::Json::Builder
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
