# frozen_string_literal: true

require 'spec_helper'

describe Doorkeeper::Orm::Dynamodb do
  describe '.run_hooks' do
    it 'does not raise errors' do
      expect { described_class.run_hooks }.not_to raise_error
    end
  end

  describe 'autoloading' do
    it 'autoloads AccessToken' do
      expect { Doorkeeper::Orm::Dynamodb::AccessToken }.not_to raise_error
    end
  end
end