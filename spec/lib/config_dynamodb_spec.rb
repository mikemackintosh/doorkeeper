# frozen_string_literal: true

require 'spec_helper'

describe Doorkeeper::Config do
  describe '#use_dynamodb_for_tokens' do
    let(:config) do
      Doorkeeper::Config::Builder.new do |builder|
        builder.use_dynamodb_for_tokens(
          region: 'us-west-2',
          table_name: 'my_oauth_tokens',
          access_key_id: 'test_key',
          secret_access_key: 'test_secret'
        )
      end.build
    end

    it 'sets the orm to dynamodb' do
      expect(config.orm).to eq(:dynamodb)
    end

    it 'sets the dynamodb region' do
      expect(config.dynamodb_region).to eq('us-west-2')
    end

    it 'sets the dynamodb table name' do
      expect(config.dynamodb_access_tokens_table).to eq('my_oauth_tokens')
    end

    it 'sets the access key id' do
      expect(config.dynamodb_access_key_id).to eq('test_key')
    end

    it 'sets the secret access key' do
      expect(config.dynamodb_secret_access_key).to eq('test_secret')
    end

    it 'sets the correct access token class' do
      expect(config.access_token_class).to eq('Doorkeeper::Orm::Dynamodb::AccessToken')
    end
  end

  describe 'partial configuration' do
    let(:config) do
      Doorkeeper::Config::Builder.new do |builder|
        builder.use_dynamodb_for_tokens(region: 'eu-central-1')
      end.build
    end

    it 'allows partial configuration' do
      expect(config.orm).to eq(:dynamodb)
      expect(config.dynamodb_region).to eq('eu-central-1')
      expect(config.dynamodb_access_tokens_table).to be_nil
      expect(config.dynamodb_access_key_id).to be_nil
      expect(config.dynamodb_secret_access_key).to be_nil
    end
  end
end