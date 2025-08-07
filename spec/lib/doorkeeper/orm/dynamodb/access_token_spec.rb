# frozen_string_literal: true

require 'spec_helper'
require 'aws-sdk-dynamodb'

describe Doorkeeper::Orm::Dynamodb::AccessToken do
  before do
    # Mock DynamoDB client
    @mock_client = instance_double(Aws::DynamoDB::Client)
    allow(described_class).to receive(:dynamodb_client).and_return(@mock_client)
    allow(described_class).to receive(:table_name).and_return('test_tokens')
  end

  let(:application) { double('Application', id: 'app123') }
  let(:resource_owner) { double('User', id: 'user123') }
  
  describe '.create!' do
    it 'creates a new access token in DynamoDB' do
      expect(@mock_client).to receive(:put_item) do |args|
        expect(args[:table_name]).to eq('test_tokens')
        expect(args[:item][:application_id]).to eq('app123')
        expect(args[:item][:resource_owner_id]).to eq('user123')
        expect(args[:item][:scopes]).to eq('read write')
        expect(args[:item]).to have_key(:token_hash)
        expect(args[:item]).to have_key(:created_at)
      end

      token = described_class.create!(
        application_id: 'app123',
        resource_owner_id: 'user123',
        scopes: 'read write',
        expires_in: 7200
      )

      expect(token).to be_a(described_class)
      expect(token.application_id).to eq('app123')
      expect(token.resource_owner_id).to eq('user123')
      expect(token.scopes).to eq('read write')
    end

    it 'includes refresh token when use_refresh_token is true' do
      expect(@mock_client).to receive(:put_item) do |args|
        expect(args[:item]).to have_key(:refresh_token_hash)
      end

      token = described_class.new(
        application_id: 'app123',
        resource_owner_id: 'user123',
        scopes: 'read',
        expires_in: 7200
      )
      token.instance_variable_set(:@use_refresh_token, true)
      token.save!
    end

    it 'includes TTL for automatic cleanup' do
      created_time = Time.current
      allow(Time).to receive(:current).and_return(created_time)

      expect(@mock_client).to receive(:put_item) do |args|
        expected_ttl = created_time.to_i + 7200
        expect(args[:item][:ttl]).to eq(expected_ttl)
      end

      described_class.create!(
        application_id: 'app123',
        resource_owner_id: 'user123',
        scopes: 'read',
        expires_in: 7200
      )
    end
  end

  describe '.by_token' do
    it 'finds token by token value' do
      mock_response = double('Response', items: [
        {
          'id' => 'token123',
          'token_hash' => 'hashed_token',
          'application_id' => 'app123',
          'resource_owner_id' => 'user123',
          'scopes' => 'read',
          'created_at' => Time.current.to_i,
          'expires_in' => 7200
        }
      ])

      expect(@mock_client).to receive(:query)
        .with(hash_including(
          table_name: 'test_tokens',
          index_name: 'token-index',
          key_condition_expression: 'token_hash = :token_hash'
        ))
        .and_return(mock_response)

      token = described_class.by_token('raw_token_value')
      expect(token).to be_a(described_class)
      expect(token.id).to eq('token123')
      expect(token.application_id).to eq('app123')
    end

    it 'returns nil when token not found' do
      mock_response = double('Response', items: [])
      
      expect(@mock_client).to receive(:query).and_return(mock_response)

      token = described_class.by_token('nonexistent_token')
      expect(token).to be_nil
    end
  end

  describe '.by_refresh_token' do
    it 'finds token by refresh token value' do
      mock_response = double('Response', items: [
        {
          'id' => 'token123',
          'refresh_token_hash' => 'hashed_refresh_token',
          'application_id' => 'app123',
          'resource_owner_id' => 'user123',
          'scopes' => 'read',
          'created_at' => Time.current.to_i,
          'expires_in' => 7200
        }
      ])

      expect(@mock_client).to receive(:query)
        .with(hash_including(
          table_name: 'test_tokens',
          index_name: 'refresh-token-index',
          key_condition_expression: 'refresh_token_hash = :refresh_token_hash'
        ))
        .and_return(mock_response)

      token = described_class.by_refresh_token('raw_refresh_token_value')
      expect(token).to be_a(described_class)
      expect(token.id).to eq('token123')
    end
  end

  describe '.revoke_all_for' do
    it 'revokes all tokens for application and resource owner' do
      mock_response = double('Response', items: [
        { 'id' => 'token1' },
        { 'id' => 'token2' }
      ])

      expect(@mock_client).to receive(:query)
        .with(hash_including(
          index_name: 'application-resource-owner-index',
          key_condition_expression: 'application_id = :app_id AND resource_owner_id = :owner_id'
        ))
        .and_return(mock_response)

      expect(@mock_client).to receive(:update_item).twice do |args|
        expect(args[:table_name]).to eq('test_tokens')
        expect(args[:update_expression]).to eq('SET revoked_at = :revoked_at')
        expect(args[:expression_attribute_values]).to have_key(:revoked_at)
      end

      described_class.revoke_all_for('app123', resource_owner)
    end
  end

  describe '.find_or_create_for' do
    context 'when reuse_access_token is enabled' do
      before do
        allow(Doorkeeper.config).to receive(:reuse_access_token).and_return(true)
      end

      it 'returns existing reusable token' do
        existing_token = described_class.new(
          id: 'existing123',
          application_id: 'app123',
          resource_owner_id: 'user123',
          scopes: 'read',
          created_at: Time.current,
          expires_in: 7200
        )

        expect(described_class).to receive(:matching_token_for)
          .and_return(existing_token)
        expect(existing_token).to receive(:reusable?).and_return(true)

        token = described_class.find_or_create_for(
          application: application,
          resource_owner: resource_owner,
          scopes: 'read'
        )

        expect(token).to eq(existing_token)
      end
    end

    context 'when reuse_access_token is disabled' do
      before do
        allow(Doorkeeper.config).to receive(:reuse_access_token).and_return(false)
      end

      it 'creates new token' do
        expect(@mock_client).to receive(:put_item)

        token = described_class.find_or_create_for(
          application: application,
          resource_owner: resource_owner,
          scopes: 'read',
          expires_in: 7200
        )

        expect(token).to be_a(described_class)
      end
    end
  end

  describe '#revoke' do
    it 'sets revoked_at timestamp' do
      token = described_class.new(id: 'token123')
      freeze_time = Time.current

      expect(@mock_client).to receive(:put_item) do |args|
        expect(args[:item][:revoked_at]).to be_within(1).of(freeze_time.to_i)
      end

      Timecop.freeze(freeze_time) do
        token.revoke
        expect(token.revoked_at).to be_within(1.second).of(freeze_time)
      end
    end
  end

  describe '#expired?' do
    it 'returns true when token has expired' do
      created_time = 2.hours.ago
      token = described_class.new(
        created_at: created_time,
        expires_in: 3600 # 1 hour
      )

      expect(token.expired?).to be true
    end

    it 'returns false when token has not expired' do
      created_time = 30.minutes.ago
      token = described_class.new(
        created_at: created_time,
        expires_in: 3600 # 1 hour
      )

      expect(token.expired?).to be false
    end

    it 'returns false when expires_in is nil' do
      token = described_class.new(expires_in: nil)
      expect(token.expired?).to be false
    end
  end

  describe '#accessible?' do
    it 'returns false for expired tokens' do
      token = described_class.new(
        created_at: 2.hours.ago,
        expires_in: 3600
      )

      expect(token.accessible?).to be false
    end

    it 'returns false for revoked tokens' do
      token = described_class.new(
        revoked_at: 1.hour.ago,
        expires_in: 7200
      )

      expect(token.accessible?).to be false
    end

    it 'returns true for valid tokens' do
      token = described_class.new(
        created_at: 30.minutes.ago,
        expires_in: 7200,
        revoked_at: nil
      )

      expect(token.accessible?).to be true
    end
  end
end