# frozen_string_literal: true

module Doorkeeper
  autoload :AccessToken, "doorkeeper/orm/dynamodb/access_token"
  autoload :Application, "doorkeeper/orm/dynamodb/application"

  # DynamoDB ORM for Doorkeeper entity models.
  # Provides DynamoDB-based storage for OAuth tokens to prevent
  # ephemeral tokens from being stored in persistent database.
  #
  # Key features:
  #   * TTL-based automatic token expiration
  #   * High-performance token lookups
  #   * Separate table design for access tokens
  #
  module Orm
    module Dynamodb
      autoload :AccessToken, "doorkeeper/orm/dynamodb/access_token"

      def self.run_hooks
        # No associations needed for DynamoDB
      end
    end
  end
end