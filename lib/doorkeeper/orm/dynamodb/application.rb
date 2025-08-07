# frozen_string_literal: true

module Doorkeeper
  module Orm
    module Dynamodb
      # Stub Application class for DynamoDB implementation.
      # Since applications are typically long-lived and need rich querying,
      # they should remain in the primary database while only tokens use DynamoDB.
      class Application
        def self.find(id)
          # Delegate to ActiveRecord implementation
          Doorkeeper.config.application_model.find(id)
        end

        def self.find_by(attributes)
          # Delegate to ActiveRecord implementation  
          Doorkeeper.config.application_model.find_by(attributes)
        end
      end
    end
  end
end