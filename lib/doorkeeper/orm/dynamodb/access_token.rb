# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'doorkeeper/models/access_token_mixin'

module Doorkeeper
  module Orm
    module Dynamodb
      class AccessToken
        include Doorkeeper::AccessTokenMixin

        # DynamoDB client
        def self.dynamodb_client
          @dynamodb_client ||= Aws::DynamoDB::Client.new(
            region: Doorkeeper.config.dynamodb_region || ENV['AWS_DEFAULT_REGION'] || 'us-east-1',
            credentials: dynamodb_credentials
          )
        end

        def self.dynamodb_credentials
          if Doorkeeper.config.dynamodb_access_key_id && Doorkeeper.config.dynamodb_secret_access_key
            Aws::Credentials.new(
              Doorkeeper.config.dynamodb_access_key_id,
              Doorkeeper.config.dynamodb_secret_access_key
            )
          end
        end

        def self.table_name
          Doorkeeper.config.dynamodb_access_tokens_table || 'oauth_access_tokens'
        end

        # Core attributes
        attr_accessor :id, :token, :refresh_token, :expires_in, :revoked_at, :created_at, 
                     :scopes, :application_id, :resource_owner_id, :resource_owner_type,
                     :previous_refresh_token

        def initialize(attributes = {})
          @id = attributes[:id] || SecureRandom.uuid
          @token = attributes[:token]
          @refresh_token = attributes[:refresh_token]
          @expires_in = attributes[:expires_in]
          @revoked_at = attributes[:revoked_at]
          @created_at = attributes[:created_at] || Time.current
          @scopes = attributes[:scopes] || ""
          @application_id = attributes[:application_id]
          @resource_owner_id = attributes[:resource_owner_id]
          @resource_owner_type = attributes[:resource_owner_type]
          @previous_refresh_token = attributes[:previous_refresh_token]
          
          # Set raw tokens for initial communication
          @raw_token = attributes[:raw_token] || @token
          @raw_refresh_token = attributes[:raw_refresh_token] || @refresh_token
        end

        def save!
          generate_token unless token.present?
          generate_refresh_token if use_refresh_token? && refresh_token.blank?

          item = {
            id: id,
            application_id: application_id,
            resource_owner_id: resource_owner_id,
            scopes: scopes,
            expires_in: expires_in,
            created_at: created_at.to_i,
            revoked_at: revoked_at&.to_i
          }

          # Store token based on configuration
          if Doorkeeper.config.dynamodb_hash_tokens
            item[:token_hash] = secret_strategy.store_secret(self, :token, @raw_token)
          else
            item[:token_value] = @raw_token
          end

          # Add refresh token if present
          if refresh_token.present?
            if Doorkeeper.config.dynamodb_hash_tokens
              item[:refresh_token_hash] = secret_strategy.store_secret(self, :refresh_token, @raw_refresh_token)
            else
              item[:refresh_token_value] = @raw_refresh_token
            end
          end

          # Add resource owner type if polymorphic
          if Doorkeeper.configuration.polymorphic_resource_owner?
            item[:resource_owner_type] = resource_owner_type
          end

          # Add previous refresh token if present
          if previous_refresh_token.present?
            item[:previous_refresh_token] = previous_refresh_token
          end

          # Add TTL for automatic cleanup (expires_in seconds from created_at)
          if expires_in
            item[:ttl] = created_at.to_i + expires_in
          end

          self.class.dynamodb_client.put_item(
            table_name: self.class.table_name,
            item: item
          )

          self
        end

        def save
          save!
        rescue Aws::DynamoDB::Errors::ServiceError
          false
        end

        def update!(attributes)
          attributes.each do |key, value|
            send("#{key}=", value) if respond_to?("#{key}=")
          end
          save!
        end

        def update(attributes)
          update!(attributes)
        rescue Aws::DynamoDB::Errors::ServiceError
          false
        end

        def destroy
          self.class.dynamodb_client.delete_item(
            table_name: self.class.table_name,
            key: { id: id }
          )
          true
        rescue Aws::DynamoDB::Errors::ServiceError
          false
        end

        def revoke
          self.revoked_at = Time.current
          save
        end

        def revoked?
          !!(revoked_at && revoked_at <= Time.current)
        end

        def accessible?
          !expired? && !revoked?
        end

        def expired?
          expires_in && created_at + expires_in.seconds < Time.current
        end

        def expires_at
          expires_in ? created_at + expires_in.seconds : nil
        end

        def application
          @application ||= Doorkeeper.config.application_model.find(application_id) if application_id
        end

        def resource_owner
          return nil unless resource_owner_id

          if Doorkeeper.configuration.polymorphic_resource_owner?
            resource_owner_type.constantize.find(resource_owner_id)
          else
            resource_owner_id
          end
        end

        # Class methods for token lookup
        class << self
          def create!(attributes)
            token = new(attributes)
            token.save!
            token
          end

          def create(attributes)
            token = new(attributes)
            token.save ? token : nil
          end

          def by_token(token_value)
            return nil unless token_value

            if Doorkeeper.config.dynamodb_hash_tokens
              # Use hashed token lookup for security
              hashed_token = secret_strategy.store_secret(new, :token, token_value)
              
              resp = dynamodb_client.query(
                table_name: table_name,
                index_name: 'token-hash-index',
                key_condition_expression: 'token_hash = :token_hash',
                expression_attribute_values: {
                  ':token_hash' => hashed_token
                },
                limit: 1
              )
            else
              # Use plaintext token lookup for performance
              resp = dynamodb_client.query(
                table_name: table_name,
                index_name: 'token-value-index',
                key_condition_expression: 'token_value = :token_value',
                expression_attribute_values: {
                  ':token_value' => token_value
                },
                limit: 1
              )
            end

            return nil if resp.items.empty?
            
            from_dynamodb_item(resp.items.first)
          end

          def by_refresh_token(refresh_token_value)
            return nil unless refresh_token_value

            if Doorkeeper.config.dynamodb_hash_tokens
              # Use hashed refresh token lookup for security
              hashed_refresh_token = secret_strategy.store_secret(new, :refresh_token, refresh_token_value)
              
              resp = dynamodb_client.query(
                table_name: table_name,
                index_name: 'refresh-token-hash-index',
                key_condition_expression: 'refresh_token_hash = :refresh_token_hash',
                expression_attribute_values: {
                  ':refresh_token_hash' => hashed_refresh_token
                },
                limit: 1
              )
            else
              # Use plaintext refresh token lookup for performance
              resp = dynamodb_client.query(
                table_name: table_name,
                index_name: 'refresh-token-value-index',
                key_condition_expression: 'refresh_token_value = :refresh_token_value',
                expression_attribute_values: {
                  ':refresh_token_value' => refresh_token_value
                },
                limit: 1
              )
            end

            return nil if resp.items.empty?
            
            from_dynamodb_item(resp.items.first)
          end

          def by_previous_refresh_token(previous_refresh_token)
            return nil unless previous_refresh_token

            resp = dynamodb_client.query(
              table_name: table_name,
              index_name: 'previous-refresh-token-index',
              key_condition_expression: 'previous_refresh_token = :previous_refresh_token',
              expression_attribute_values: {
                ':previous_refresh_token' => previous_refresh_token
              },
              limit: 1
            )

            return nil if resp.items.empty?
            
            from_dynamodb_item(resp.items.first)
          end

          def revoke_all_for(application_id, resource_owner, clock = Time)
            # Query for all tokens for this application and resource owner
            resp = dynamodb_client.query(
              table_name: table_name,
              index_name: 'application-resource-owner-index',
              key_condition_expression: 'application_id = :app_id AND resource_owner_id = :owner_id',
              filter_expression: 'attribute_not_exists(revoked_at)',
              expression_attribute_values: {
                ':app_id' => application_id,
                ':owner_id' => resource_owner.is_a?(Integer) ? resource_owner : resource_owner.id
              }
            )

            # Revoke each token
            resp.items.each do |item|
              dynamodb_client.update_item(
                table_name: table_name,
                key: { id: item['id'] },
                update_expression: 'SET revoked_at = :revoked_at',
                expression_attribute_values: {
                  ':revoked_at' => clock.now.utc.to_i
                }
              )
            end
          end

          def matching_token_for(application, resource_owner, scopes, custom_attributes: nil, include_expired: true)
            owner_id = resource_owner.is_a?(Integer) ? resource_owner : resource_owner&.id
            return nil unless owner_id

            # Query tokens for application and resource owner
            resp = dynamodb_client.query(
              table_name: table_name,
              index_name: 'application-resource-owner-index',
              key_condition_expression: 'application_id = :app_id AND resource_owner_id = :owner_id',
              expression_attribute_values: {
                ':app_id' => application&.id,
                ':owner_id' => owner_id
              }
            )

            matching_tokens = resp.items.map { |item| from_dynamodb_item(item) }
                                       .select { |token| !token.revoked? }
                                       .select { |token| include_expired || !token.expired? }
                                       .select { |token| scopes_match?(token.scopes, scopes, application&.scopes) }

            # Filter by custom attributes if provided
            if custom_attributes
              matching_tokens.select! do |token|
                custom_attributes_match?(token, custom_attributes)
              end
            end

            # Return most recently created
            matching_tokens.max_by(&:created_at)
          end

          def find_or_create_for(application:, resource_owner:, scopes:, **token_attributes)
            scopes = Doorkeeper::OAuth::Scopes.from_string(scopes) if scopes.is_a?(String)

            if Doorkeeper.config.reuse_access_token
              custom_attributes = extract_custom_attributes(token_attributes).presence
              access_token = matching_token_for(
                application, resource_owner, scopes, 
                custom_attributes: custom_attributes, include_expired: false
              )

              return access_token if access_token&.reusable?
            end

            create_for(
              application: application,
              resource_owner: resource_owner,
              scopes: scopes,
              **token_attributes
            )
          end

          def create_for(application:, resource_owner:, scopes:, **token_attributes)
            token_attributes[:application_id] = application&.id
            token_attributes[:scopes] = scopes.to_s

            if Doorkeeper.config.polymorphic_resource_owner?
              token_attributes[:resource_owner] = resource_owner
              token_attributes[:resource_owner_id] = resource_owner&.id
              token_attributes[:resource_owner_type] = resource_owner&.class&.name
            else
              owner_id = resource_owner.is_a?(Integer) ? resource_owner : resource_owner&.id
              token_attributes[:resource_owner_id] = owner_id
            end

            create!(token_attributes)
          end

          def authorized_tokens_for(application_id, resource_owner)
            owner_id = resource_owner.is_a?(Integer) ? resource_owner : resource_owner.id
            
            resp = dynamodb_client.query(
              table_name: table_name,
              index_name: 'application-resource-owner-index',
              key_condition_expression: 'application_id = :app_id AND resource_owner_id = :owner_id',
              filter_expression: 'attribute_not_exists(revoked_at)',
              expression_attribute_values: {
                ':app_id' => application_id,
                ':owner_id' => owner_id
              }
            )

            resp.items.map { |item| from_dynamodb_item(item) }
          end

          def last_authorized_token_for(application_id, resource_owner)
            authorized_tokens_for(application_id, resource_owner)
              .max_by(&:created_at)
          end

          def secret_strategy
            ::Doorkeeper.config.token_secret_strategy
          end

          def fallback_secret_strategy
            ::Doorkeeper.config.token_secret_fallback_strategy
          end

          private

          def from_dynamodb_item(item)
            new(
              id: item['id'],
              token: item['token_hash'], # Store hash, not plaintext
              refresh_token: item['refresh_token_hash'],
              expires_in: item['expires_in'],
              revoked_at: item['revoked_at'] ? Time.at(item['revoked_at']) : nil,
              created_at: Time.at(item['created_at']),
              scopes: item['scopes'],
              application_id: item['application_id'],
              resource_owner_id: item['resource_owner_id'],
              resource_owner_type: item['resource_owner_type'],
              previous_refresh_token: item['previous_refresh_token']
            )
          end
        end
      end
    end
  end
end