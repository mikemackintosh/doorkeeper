# DynamoDB Storage for OAuth Tokens

Doorkeeper supports storing OAuth access tokens and refresh tokens in Amazon DynamoDB instead of your primary database. This is particularly useful for preventing ephemeral tokens from cluttering your persistent database and for improved performance at scale.

## Features

- **Automatic token expiration**: Uses DynamoDB TTL to automatically clean up expired tokens
- **High performance**: DynamoDB's single-digit millisecond latency for token lookups
- **Separate storage**: Keeps ephemeral tokens out of your primary database
- **Flexible authentication**: Supports IAM roles, access keys, or default AWS credentials
- **Compatible**: Works with existing Doorkeeper OAuth flows

## Setup

### 1. Install AWS SDK

Add the AWS SDK for DynamoDB to your Gemfile:

```ruby
gem 'aws-sdk-dynamodb', '~> 1.0'
```

### 2. Create DynamoDB Table

Create a DynamoDB table for storing access tokens. The table structure depends on whether you're using performance mode or security mode.

#### For Performance Mode (`hash_tokens: false`)

```bash
aws dynamodb create-table \
  --table-name oauth_access_tokens \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=token_value,AttributeType=S \
    AttributeName=refresh_token_value,AttributeType=S \
    AttributeName=application_id,AttributeType=S \
    AttributeName=resource_owner_id,AttributeType=S \
    AttributeName=previous_refresh_token,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
    IndexName=token-value-index,KeySchema=[{AttributeName=token_value,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=10,WriteCapacityUnits=5} \
    IndexName=refresh-token-value-index,KeySchema=[{AttributeName=refresh_token_value,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=2} \
    IndexName=application-resource-owner-index,KeySchema=[{AttributeName=application_id,KeyType=HASH},{AttributeName=resource_owner_id,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=2} \
    IndexName=previous-refresh-token-index,KeySchema=[{AttributeName=previous_refresh_token,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=2,WriteCapacityUnits=1} \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --time-to-live-specification \
    AttributeName=ttl,Enabled=true
```

#### For Security Mode (`hash_tokens: true`)

```bash
aws dynamodb create-table \
  --table-name oauth_access_tokens \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=token_hash,AttributeType=S \
    AttributeName=refresh_token_hash,AttributeType=S \
    AttributeName=application_id,AttributeType=S \
    AttributeName=resource_owner_id,AttributeType=S \
    AttributeName=previous_refresh_token,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
    IndexName=token-hash-index,KeySchema=[{AttributeName=token_hash,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=10,WriteCapacityUnits=5} \
    IndexName=refresh-token-hash-index,KeySchema=[{AttributeName=refresh_token_hash,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=2} \
    IndexName=application-resource-owner-index,KeySchema=[{AttributeName=application_id,KeyType=HASH},{AttributeName=resource_owner_id,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=2} \
    IndexName=previous-refresh-token-index,KeySchema=[{AttributeName=previous_refresh_token,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=2,WriteCapacityUnits=1} \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --time-to-live-specification \
    AttributeName=ttl,Enabled=true
```

### 3. Configure Doorkeeper

In your Doorkeeper configuration (`config/initializers/doorkeeper.rb`):

```ruby
Doorkeeper.configure do
  # Configure DynamoDB for token storage
  use_dynamodb_for_tokens(
    region: 'us-east-1',
    table_name: 'oauth_access_tokens',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],     # Optional: uses IAM role if not provided
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'], # Optional: uses IAM role if not provided
    hash_tokens: false,                          # Optional: false for performance, true for security
    enable_migration: true                       # Optional: enables PostgreSQL to DynamoDB migration
  )

  # Your other Doorkeeper configuration...
  resource_owner_authenticator do
    User.find(session[:user_id])
  end

  # etc...
end
```

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `region` | AWS region for DynamoDB | `ENV['AWS_DEFAULT_REGION']` or `'us-east-1'` |
| `table_name` | DynamoDB table name | `'oauth_access_tokens'` |
| `access_key_id` | AWS access key ID | Uses default AWS credential chain |
| `secret_access_key` | AWS secret access key | Uses default AWS credential chain |
| `hash_tokens` | Store hashed tokens (security vs performance) | `false` (plaintext for performance) |
| `enable_migration` | Enable PostgreSQL to DynamoDB migration utilities | `false` |

## Token Storage Options

### Performance Mode (default: `hash_tokens: false`)

Stores tokens in plaintext in DynamoDB for maximum performance:
- **Pros**: Fastest token lookups, simple implementation, lower CPU usage
- **Cons**: Tokens visible in DynamoDB console/backups
- **Use case**: High-performance applications where tokens are short-lived and DynamoDB access is restricted

```ruby
use_dynamodb_for_tokens(
  region: 'us-east-1',
  table_name: 'oauth_access_tokens',
  hash_tokens: false  # Performance mode
)
```

### Security Mode (`hash_tokens: true`)

Stores hashed tokens in DynamoDB for maximum security:
- **Pros**: Tokens are hashed using your configured secret strategy, not visible in plaintext
- **Cons**: Slightly higher latency for token operations, more complex implementation
- **Use case**: Security-sensitive applications where token confidentiality is critical

```ruby
use_dynamodb_for_tokens(
  region: 'us-east-1',
  table_name: 'oauth_access_tokens',
  hash_tokens: true   # Security mode
)

# Also configure token hashing strategy
hash_token_secrets using: ::Doorkeeper::SecretStoring::Sha256Hash
```

## Authentication Options

### Option 1: IAM Roles (Recommended)

If your application runs on AWS (EC2, ECS, Lambda, etc.), use IAM roles for authentication. This is the most secure option as no credentials need to be stored in your application.

```ruby
Doorkeeper.configure do
  use_dynamodb_for_tokens(
    region: 'us-east-1',
    table_name: 'oauth_access_tokens'
    # No access keys needed - uses IAM role
  )
end
```

### Option 2: Access Keys

For applications running outside AWS or for development:

```ruby
Doorkeeper.configure do
  use_dynamodb_for_tokens(
    region: 'us-east-1',
    table_name: 'oauth_access_tokens',
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
  )
end
```

### Option 3: Default AWS Credentials

Uses the default AWS credential provider chain (environment variables, instance profiles, etc.):

```ruby
Doorkeeper.configure do
  use_dynamodb_for_tokens(
    region: 'us-east-1',
    table_name: 'oauth_access_tokens'
  )
end
```

## Required IAM Permissions

Your IAM user or role needs the following DynamoDB permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:REGION:ACCOUNT:table/oauth_access_tokens",
        "arn:aws:dynamodb:REGION:ACCOUNT:table/oauth_access_tokens/index/*"
      ]
    }
  ]
}
```

## How It Works

### Token Storage

- Access tokens are stored with their hashed values for security
- Each token has a TTL (time-to-live) attribute for automatic cleanup
- Refresh tokens are handled similarly to access tokens
- Applications and other OAuth entities remain in your primary database

### Token Lookup

The DynamoDB implementation provides efficient token lookups using Global Secondary Indexes (GSI):

- `token-index`: For access token lookups
- `refresh-token-index`: For refresh token lookups
- `application-resource-owner-index`: For finding tokens by application and user
- `previous-refresh-token-index`: For refresh token rotation

### Automatic Cleanup

DynamoDB's TTL feature automatically deletes expired tokens, reducing storage costs and improving performance.

## Performance Considerations

### Read/Write Capacity

- Start with 5 RCU/WCU and adjust based on your application's load
- Consider using Auto Scaling for variable workloads
- Monitor CloudWatch metrics to optimize capacity

### Indexes

The required GSIs will consume additional read/write capacity. Factor this into your capacity planning.

### Caching

DynamoDB provides single-digit millisecond latency, but you may still want to implement application-level caching for frequently accessed tokens.

## Limitations

- **Applications remain in primary database**: Only tokens are stored in DynamoDB
- **No complex queries**: DynamoDB doesn't support complex SQL-like queries
- **Eventual consistency**: Some GSI queries may have slight delays
- **Cost**: DynamoDB pricing is different from relational databases

## Migration from Database Storage

If you're migrating from database storage to DynamoDB:

1. **Set up DynamoDB table** as described above
2. **Update Doorkeeper configuration** to use DynamoDB
3. **Deploy the changes** - new tokens will use DynamoDB
4. **Optional**: Migrate existing tokens or let them expire naturally

## Troubleshooting

### Connection Issues

- Verify AWS credentials and region settings
- Check IAM permissions for DynamoDB access
- Ensure the DynamoDB table exists and is active

### Performance Issues

- Monitor CloudWatch metrics for throttling
- Consider increasing read/write capacity
- Check GSI capacity utilization

### Token Not Found Errors

- Verify table name configuration
- Check that required indexes exist
- Ensure tokens aren't being cleaned up prematurely by TTL

## Example Application

Here's a complete example configuration:

```ruby
# config/initializers/doorkeeper.rb
Doorkeeper.configure do
  # Use DynamoDB for token storage
  use_dynamodb_for_tokens(
    region: Rails.env.production? ? 'us-east-1' : 'us-west-2',
    table_name: "oauth_tokens_#{Rails.env}",
    # Uses IAM role in production, access keys in development
    access_key_id: Rails.env.production? ? nil : ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: Rails.env.production? ? nil : ENV['AWS_SECRET_ACCESS_KEY']
  )

  # Standard Doorkeeper configuration
  resource_owner_authenticator do
    User.find(session[:user_id]) if session[:user_id]
  end

  grant_flows %w[authorization_code client_credentials]
  
  access_token_expires_in 2.hours
  use_refresh_token true
  
  # Hash tokens for security
  hash_token_secrets
end
```

This setup provides a robust, scalable OAuth token storage solution using Amazon DynamoDB while keeping your application data in your primary database.