# frozen_string_literal: true

# Doorkeeper configuration with DynamoDB token storage
#
# This example shows how to configure Doorkeeper to use Amazon DynamoDB
# for storing OAuth access tokens and refresh tokens instead of your 
# primary database.

Doorkeeper.configure do
  # == Resource Owner Authenticator
  #
  # Provided resource owner ID will be used to fetch the resource owner object.
  # Leave it nil to disable resource owner authentication (password grant will not work).
  resource_owner_authenticator do
    # current_user || warden.authenticate!(scope: :user)
    User.find(session[:user_id]) if session[:user_id]
  end

  # == DynamoDB Configuration
  #
  # Configure Doorkeeper to use DynamoDB for token storage.
  # This prevents ephemeral tokens from cluttering your primary database
  # and provides automatic token expiration through DynamoDB TTL.
  #
  # Requirements:
  # 1. Add 'aws-sdk-dynamodb' to your Gemfile
  # 2. Create DynamoDB table with required indexes (see DYNAMODB_STORAGE.md)
  # 3. Configure AWS credentials (IAM role recommended)
  #
  use_dynamodb_for_tokens(
    region: ENV['AWS_REGION'] || 'us-east-1',
    table_name: ENV['DYNAMODB_OAUTH_TOKENS_TABLE'] || 'oauth_access_tokens',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],     # Optional: uses IAM role if not provided
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'] # Optional: uses IAM role if not provided
  )

  # == Admin Authenticator
  #
  # Admin authenticator will be used to authenticate admin panel.
  admin_authenticator do
    redirect_to new_user_session_path unless current_user&.admin?
  end

  # == Grant Flows
  #
  # Available grant flows:
  #
  # Enabe/disable grants and other authz flows:
  grant_flows %w[authorization_code client_credentials]

  # == Scopes
  #
  # Define scopes for your provider
  default_scopes :public
  optional_scopes :read, :write, :admin

  # == Token Security
  #
  # Hash tokens for better security
  hash_token_secrets using: ::Doorkeeper::SecretStoring::Sha256Hash

  # == Token Expiration
  #
  # Access token expiration time (default 2 hours)
  access_token_expires_in 2.hours

  # Use refresh tokens
  use_refresh_token

  # == Redirect URI Settings
  #
  # Enforce configured scopes for applications
  enforce_configured_scopes

  # Force SSL in production for security
  force_ssl_in_redirect_uri !Rails.env.development?

  # == PKCE (Proof Key for Code Exchange)
  #
  # Force PKCE for public clients
  # force_pkce

  # == Application Owner
  #
  # Enable application owner confirmation
  # enable_application_owner confirmation: true

  # == Custom Attributes
  #
  # Allow additional attributes for access tokens
  # custom_access_token_attributes %i[tenant_id organization_id]

  # == Hooks
  #
  # Define hooks for various OAuth events
  
  # before_successful_authorization do |controller, context|
  #   # Log successful authorization
  # end

  # after_successful_authorization do |controller, context|
  #   # Send notification, track metrics, etc.
  # end
end

# == DynamoDB Table Setup
#
# Make sure your DynamoDB table is created with the following structure:
#
# Table: oauth_access_tokens
# Primary Key: id (String)
# TTL Attribute: ttl
#
# Global Secondary Indexes:
# 1. token-index: token_hash (Hash)
# 2. refresh-token-index: refresh_token_hash (Hash)  
# 3. application-resource-owner-index: application_id (Hash), resource_owner_id (Range)
# 4. previous-refresh-token-index: previous_refresh_token (Hash)
#
# See docs/DYNAMODB_STORAGE.md for complete setup instructions.