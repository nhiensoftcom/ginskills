#!/usr/bin/env bash
# =============================================================================
# Secret Patterns Database -- Security Scanner
# =============================================================================
#
# Sourced by other scanner scripts. Do NOT execute directly.
#
# Format (each array element):
#   'SEVERITY|CATEGORY|NAME|REGEX|DESCRIPTION'
#
# SEVERITY  : CRITICAL, HIGH, MEDIUM, LOW
# CATEGORY  : cloud, payment, vcs, communication, ai, auth, database,
#             registry, infra, analytics, saas, crypto, generic
# NAME      : UPPER_SNAKE_CASE identifier used in finding reports
# REGEX     : POSIX-extended regex compatible with grep -E
# DESCRIPTION: Human-readable description of what was matched
#
# Two arrays are defined:
#   SECRET_PATTERNS       -- standalone patterns; match on their own
#   CONTEXTUAL_PATTERNS   -- require surrounding context (broader grep then validate)
#
# Supporting arrays:
#   EXCLUDE_PATHS         -- path fragments to skip during scanning
#   FALSE_POSITIVE_PATTERNS -- literal strings that indicate a non-secret
#   SCAN_EXTENSIONS       -- file extensions to include in scans
#
# Note on quoting: all pattern entries use single quotes so that regex
# metacharacters are never interpreted by bash. The REGEX field is extracted
# by splitting on '|' in the consuming script.
#
# =============================================================================

# Guard against double-sourcing
if [ "${_SECRET_PATTERNS_LOADED:-}" = "1" ]; then
  return 0
fi
_SECRET_PATTERNS_LOADED=1

# =============================================================================
# STANDALONE PATTERNS
# These regexes are distinctive enough to match without additional context.
# =============================================================================

SECRET_PATTERNS=(

  # ---------------------------------------------------------------------------
  # Cloud -- AWS
  # ---------------------------------------------------------------------------

  'CRITICAL|cloud|AWS_ACCESS_KEY_ID|AKIA[0-9A-Z]{16}|AWS Access Key ID'

  'CRITICAL|cloud|AWS_MWS_AUTH_TOKEN|amzn\.mws\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|AWS Marketplace Web Service auth token'

  'LOW|cloud|AWS_ARN|arn:aws:[a-zA-Z0-9\-]+:[a-zA-Z0-9\-]*:[0-9]{12}:|AWS Resource Name -- may indicate account enumeration'

  'HIGH|cloud|AWS_SESSION_TOKEN_PREFIX|FwoGZXIvYXdzE|AWS STS session token prefix (temporary credential)'

  # ---------------------------------------------------------------------------
  # Cloud -- Google / GCP
  # ---------------------------------------------------------------------------

  'CRITICAL|cloud|GCP_API_KEY|AIza[0-9A-Za-z\-_]{35}|Google Cloud / Firebase / Gemini API key'

  'HIGH|cloud|GOOGLE_OAUTH_CLIENT|[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com|Google OAuth client ID'

  'CRITICAL|cloud|GOOGLE_SERVICE_ACCOUNT|"type"\s*:\s*"service_account"|Google service account JSON credential file'

  # ---------------------------------------------------------------------------
  # Cloud -- Azure
  # ---------------------------------------------------------------------------

  'CRITICAL|cloud|AZURE_STORAGE_KEY|DefaultEndpointsProtocol=https;AccountName=[^;]+;AccountKey=[A-Za-z0-9+/=]{88}|Azure Storage account connection string with embedded key'

  # ---------------------------------------------------------------------------
  # Payment Processors -- Stripe
  # ---------------------------------------------------------------------------

  'CRITICAL|payment|STRIPE_SECRET_KEY|sk_live_[0-9a-zA-Z]{24,}|Stripe live secret key'

  'MEDIUM|payment|STRIPE_TEST_KEY|sk_test_[0-9a-zA-Z]{24,}|Stripe test secret key (not production but still sensitive)'

  'LOW|payment|STRIPE_PUBLISHABLE_LIVE|pk_live_[0-9a-zA-Z]{24,}|Stripe live publishable key (public by design but confirms live environment)'

  'HIGH|payment|STRIPE_RESTRICTED_KEY|rk_live_[0-9a-zA-Z]{24,}|Stripe live restricted key'

  'HIGH|payment|STRIPE_WEBHOOK_SECRET|whsec_[0-9a-zA-Z]{24,}|Stripe webhook signing secret'

  # ---------------------------------------------------------------------------
  # Payment Processors -- Square
  # ---------------------------------------------------------------------------

  'CRITICAL|payment|SQUARE_ACCESS_TOKEN|sq0atp-[0-9A-Za-z\-_]{22}|Square production access token'

  'CRITICAL|payment|SQUARE_OAUTH_SECRET|sq0csp-[0-9A-Za-z\-_]{43}|Square OAuth application secret'

  # ---------------------------------------------------------------------------
  # Version Control & CI/CD -- GitHub
  # ---------------------------------------------------------------------------

  'CRITICAL|vcs|GITHUB_PAT_CLASSIC|ghp_[0-9a-zA-Z]{36}|GitHub classic personal access token'

  'CRITICAL|vcs|GITHUB_OAUTH_TOKEN|gho_[0-9a-zA-Z]{36}|GitHub OAuth access token'

  'CRITICAL|vcs|GITHUB_USER_TO_SERVER|ghu_[0-9a-zA-Z]{36}|GitHub user-to-server token (GitHub App)'

  'CRITICAL|vcs|GITHUB_SERVER_TO_SERVER|ghs_[0-9a-zA-Z]{36}|GitHub server-to-server token (GitHub App installation)'

  'CRITICAL|vcs|GITHUB_REFRESH_TOKEN|ghr_[0-9a-zA-Z]{36}|GitHub refresh token'

  'CRITICAL|vcs|GITHUB_FINE_GRAINED_PAT|github_pat_[0-9a-zA-Z_]{82}|GitHub fine-grained personal access token'

  # ---------------------------------------------------------------------------
  # Version Control & CI/CD -- GitLab
  # ---------------------------------------------------------------------------

  'CRITICAL|vcs|GITLAB_PAT|glpat-[0-9a-zA-Z\-_]{20,}|GitLab personal access token'

  'CRITICAL|vcs|GITLAB_PIPELINE_TOKEN|glptt-[0-9a-f]{40}|GitLab pipeline trigger token'

  'HIGH|vcs|GITLAB_RUNNER_TOKEN|glrt-[0-9a-zA-Z\-_]{20,}|GitLab runner registration token'

  # ---------------------------------------------------------------------------
  # Communication -- Slack
  # ---------------------------------------------------------------------------

  'CRITICAL|communication|SLACK_BOT_TOKEN|xoxb-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24}|Slack bot token'

  'CRITICAL|communication|SLACK_USER_TOKEN|xoxp-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24,}|Slack user OAuth token'

  'CRITICAL|communication|SLACK_APP_TOKEN|xapp-[0-9]-[A-Z0-9]{10,}-[0-9]{10,}-[a-zA-Z0-9]{64}|Slack app-level token'

  'HIGH|communication|SLACK_WEBHOOK_URL|https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[a-zA-Z0-9]{24}|Slack incoming webhook URL'

  # ---------------------------------------------------------------------------
  # Communication -- Discord
  # ---------------------------------------------------------------------------

  'CRITICAL|communication|DISCORD_BOT_TOKEN|[MN][A-Za-z0-9]{23,}\.[A-Za-z0-9_\-]{6}\.[A-Za-z0-9_\-]{27}|Discord bot token'

  'MEDIUM|communication|DISCORD_WEBHOOK_URL|https://discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9\-_]+|Discord webhook URL'

  # ---------------------------------------------------------------------------
  # Communication -- Twilio
  # ---------------------------------------------------------------------------

  'HIGH|communication|TWILIO_ACCOUNT_SID|AC[0-9a-f]{32}|Twilio account SID'

  # ---------------------------------------------------------------------------
  # Communication -- SendGrid / Email
  # ---------------------------------------------------------------------------

  'CRITICAL|communication|SENDGRID_API_KEY|SG\.[0-9A-Za-z\-_]{22}\.[0-9A-Za-z\-_]{43}|SendGrid API key'

  'HIGH|communication|MAILGUN_API_KEY|key-[0-9a-zA-Z]{32}|Mailgun API key'

  'HIGH|communication|MAILCHIMP_API_KEY|[0-9a-f]{32}-us[0-9]{1,2}|Mailchimp API key'

  # ---------------------------------------------------------------------------
  # AI / ML Providers
  # ---------------------------------------------------------------------------

  'CRITICAL|ai|OPENAI_API_KEY_LEGACY|sk-[0-9a-zA-Z]{48}|OpenAI API key (legacy format)'

  'CRITICAL|ai|OPENAI_API_KEY_PROJECT|sk-proj-[0-9a-zA-Z\-_]{80,}|OpenAI API key (project-scoped format)'

  'MEDIUM|ai|OPENAI_ORG_ID|org-[0-9a-zA-Z]{24}|OpenAI organization identifier'

  'CRITICAL|ai|ANTHROPIC_API_KEY|sk-ant-api[0-9]{2}-[0-9a-zA-Z\-_]{80,}|Anthropic Claude API key'

  'CRITICAL|ai|HUGGING_FACE_TOKEN|hf_[0-9a-zA-Z]{34,}|Hugging Face user access token'

  'CRITICAL|ai|REPLICATE_API_TOKEN|r8_[0-9a-zA-Z]{36}|Replicate API token'

  # ---------------------------------------------------------------------------
  # Auth & Identity
  # ---------------------------------------------------------------------------

  'CRITICAL|auth|FIREBASE_FCM_SERVER_KEY|AAAA[A-Za-z0-9_\-]{7}:[A-Za-z0-9_\-]{140}|Firebase Cloud Messaging legacy server key'

  'CRITICAL|auth|CLERK_SECRET_KEY|sk_live_[0-9a-zA-Z]{40,}|Clerk production secret key'

  # ---------------------------------------------------------------------------
  # Database Connection Strings
  # ---------------------------------------------------------------------------

  'CRITICAL|database|MONGODB_URI|mongodb(\+srv)?://[^[:space:]"]{10,}|MongoDB connection string (URI format)'

  'CRITICAL|database|POSTGRESQL_URI|postgres(ql)?://[^[:space:]"]{10,}|PostgreSQL connection string (URI format)'

  'CRITICAL|database|MYSQL_URI|mysql://[^[:space:]"]{10,}|MySQL connection string (URI format)'

  'HIGH|database|REDIS_URI|rediss?://[^[:space:]"]{10,}|Redis connection string (URI format)'

  'HIGH|database|GENERIC_CONN_WITH_PASSWORD|://[^:[:space:]]+:[^@[:space:]]+@[^[:space:]"]+|Generic connection string with embedded credentials'

  # ---------------------------------------------------------------------------
  # Package Registries
  # ---------------------------------------------------------------------------

  'CRITICAL|registry|NPM_TOKEN|npm_[0-9a-zA-Z]{36}|npm publish/automation token'

  'HIGH|registry|NPM_AUTH_TOKEN_NPMRC|//registry\.npmjs\.org/:_authToken=|npm auth token hardcoded in .npmrc'

  'CRITICAL|registry|PYPI_TOKEN|pypi-[0-9a-zA-Z\-_]{100,}|PyPI upload token'

  'CRITICAL|registry|RUBYGEMS_API_KEY|rubygems_[0-9a-f]{48}|RubyGems API key'

  'CRITICAL|registry|NUGET_API_KEY|oy2[0-9a-z]{43}|NuGet.org API key'

  # ---------------------------------------------------------------------------
  # Infrastructure & Hosting
  # ---------------------------------------------------------------------------

  'CRITICAL|infra|DIGITALOCEAN_TOKEN|dop_v1_[0-9a-f]{64}|DigitalOcean personal access token'

  'CRITICAL|infra|DIGITALOCEAN_OAUTH|doo_v1_[0-9a-f]{64}|DigitalOcean OAuth token'

  'CRITICAL|infra|RAILWAY_TOKEN|railway_[0-9a-zA-Z]{32,}|Railway deployment token'

  'CRITICAL|infra|FLY_IO_TOKEN|fo1_[0-9a-zA-Z_\-]{39}|Fly.io access token'

  'CRITICAL|infra|RENDER_API_KEY|rnd_[0-9a-zA-Z]{32,}|Render.com API key'

  'CRITICAL|infra|TERRAFORM_CLOUD_TOKEN|[a-zA-Z0-9]{14}\.atlasv1\.[a-zA-Z0-9\-_]{60,}|Terraform Cloud / Atlas token'

  'CRITICAL|infra|HASHICORP_VAULT_TOKEN|hvs\.[a-zA-Z0-9\-_]{90,}|HashiCorp Vault service token'

  # ---------------------------------------------------------------------------
  # Analytics & Monitoring
  # ---------------------------------------------------------------------------

  'HIGH|analytics|SENTRY_DSN|https://[0-9a-f]+@[a-z0-9]+\.ingest\.sentry\.io/[0-9]+|Sentry DSN reveals project and ingest endpoint'

  'HIGH|analytics|NEW_RELIC_LICENSE_KEY|NRAK-[0-9A-Z]{27}|New Relic license or ingest key'

  # ---------------------------------------------------------------------------
  # SaaS & Productivity
  # ---------------------------------------------------------------------------

  'CRITICAL|saas|LINEAR_API_KEY|lin_api_[0-9a-zA-Z]{40,}|Linear API key'

  'CRITICAL|saas|NOTION_TOKEN|secret_[0-9a-zA-Z]{43}|Notion integration token'

  'HIGH|saas|AIRTABLE_API_KEY|key[0-9a-zA-Z]{14}|Airtable personal API key (legacy)'

  'CRITICAL|saas|PLANETSCALE_TOKEN|pscale_tkn_[0-9a-zA-Z\-_]{43}|PlanetScale service token'

  'CRITICAL|saas|PLANETSCALE_PASSWORD|pscale_pw_[0-9a-zA-Z\-_]{43}|PlanetScale database password'

  'CRITICAL|saas|DOPPLER_TOKEN|dp\.pt\.[0-9a-zA-Z]{43}|Doppler service token'

  'HIGH|saas|EXPO_TOKEN|expo_[0-9a-zA-Z]{40,}|Expo access token'

  # ---------------------------------------------------------------------------
  # SaaS -- Shopify
  # ---------------------------------------------------------------------------

  'CRITICAL|saas|SHOPIFY_ACCESS_TOKEN|shpat_[0-9a-fA-F]{32}|Shopify admin API access token'

  'CRITICAL|saas|SHOPIFY_CUSTOM_APP_TOKEN|shpca_[0-9a-fA-F]{32}|Shopify custom app token'

  'CRITICAL|saas|SHOPIFY_PRIVATE_APP_TOKEN|shppa_[0-9a-fA-F]{32}|Shopify private app token'

  'HIGH|saas|SHOPIFY_SHARED_SECRET|shpss_[0-9a-fA-F]{32}|Shopify shared secret used for webhook validation'

  # ---------------------------------------------------------------------------
  # SaaS -- Grafana
  # ---------------------------------------------------------------------------

  'CRITICAL|saas|GRAFANA_API_KEY|eyJrIjoi[A-Za-z0-9\-_]+=*|Grafana API key (JWT-encoded)'

  'CRITICAL|saas|GRAFANA_CLOUD_TOKEN|glc_[A-Za-z0-9\-_+/]{32,}|Grafana Cloud access token'

  'CRITICAL|saas|GRAFANA_SERVICE_ACCOUNT_TOKEN|glsa_[A-Za-z0-9\-_+/]{32,}_[A-Fa-f0-9]{8}|Grafana service account token'

  # ---------------------------------------------------------------------------
  # Messaging -- Telegram
  # ---------------------------------------------------------------------------

  'CRITICAL|communication|TELEGRAM_BOT_TOKEN|[0-9]{8,10}:[0-9A-Za-z_\-]{35}|Telegram bot token'

  # ---------------------------------------------------------------------------
  # Cryptographic Material (PEM header lines)
  # ---------------------------------------------------------------------------

  'CRITICAL|crypto|RSA_PRIVATE_KEY|-----BEGIN RSA PRIVATE KEY-----|RSA private key PEM block'

  'CRITICAL|crypto|EC_PRIVATE_KEY|-----BEGIN EC PRIVATE KEY-----|Elliptic curve private key PEM block'

  'CRITICAL|crypto|DSA_PRIVATE_KEY|-----BEGIN DSA PRIVATE KEY-----|DSA private key PEM block'

  'CRITICAL|crypto|OPENSSH_PRIVATE_KEY|-----BEGIN OPENSSH PRIVATE KEY-----|OpenSSH private key PEM block'

  'CRITICAL|crypto|PGP_PRIVATE_KEY|-----BEGIN PGP PRIVATE KEY BLOCK-----|PGP or GPG private key block'

  'CRITICAL|crypto|PKCS8_PRIVATE_KEY|-----BEGIN PRIVATE KEY-----|PKCS#8 unencrypted private key PEM block'

  'CRITICAL|crypto|PKCS8_ENCRYPTED_KEY|-----BEGIN ENCRYPTED PRIVATE KEY-----|PKCS#8 encrypted private key PEM block'

  # ---------------------------------------------------------------------------
  # Generic -- High-Entropy Assignments (lower-ambiguity standalone forms)
  # ---------------------------------------------------------------------------

  'HIGH|generic|BEARER_TOKEN_HARDCODED|Bearer[[:space:]]+[a-zA-Z0-9\-_.~+/]+=*|Hardcoded Bearer token in source code'

  'MEDIUM|generic|BASIC_AUTH_HARDCODED|Basic[[:space:]]+[A-Za-z0-9+/=]{20,}|Hardcoded Basic auth credential'

  'HIGH|generic|URL_WITH_CREDENTIALS|https?://[^:[:space:]"]+:[^@[:space:]"]+@[^[:space:]"]+|URL containing embedded username and password'

)

# =============================================================================
# CONTEXTUAL PATTERNS
# These patterns are too generic on their own. The scanner must also verify
# that the matched line -- or surrounding lines -- contains the context hint
# listed in the CONTEXT: suffix of the DESCRIPTION field.
#
# Convention: the DESCRIPTION field ends with |CONTEXT:<keyword> so that
# scanner scripts can split on '|' to extract the required context word.
# =============================================================================

CONTEXTUAL_PATTERNS=(

  # ---------------------------------------------------------------------------
  # Cloud -- AWS
  # ---------------------------------------------------------------------------

  'CRITICAL|cloud|AWS_SECRET_ACCESS_KEY|aws.{0,20}["'"'"'][0-9a-zA-Z/+]{40}["'"'"']|AWS secret access key (aws keyword must appear nearby)|CONTEXT:aws'

  'HIGH|cloud|AZURE_AD_CLIENT_SECRET|[0-9a-zA-Z\-_.~]{34,}|Azure AD client secret (azure or tenant keyword must appear nearby)|CONTEXT:azure'

  # ---------------------------------------------------------------------------
  # Payment -- PayPal
  # ---------------------------------------------------------------------------

  'CRITICAL|payment|PAYPAL_CLIENT_SECRET|paypal.{0,20}secret.{0,20}["'"'"'][0-9a-zA-Z]{32,}["'"'"']|PayPal client secret (paypal keyword required)|CONTEXT:paypal'

  # ---------------------------------------------------------------------------
  # Version Control & CI/CD
  # ---------------------------------------------------------------------------

  'HIGH|vcs|BITBUCKET_APP_PASSWORD|bitbucket.{0,30}["'"'"'][0-9a-zA-Z]{25,}["'"'"']|Bitbucket app password (bitbucket keyword required)|CONTEXT:bitbucket'

  'HIGH|vcs|CIRCLECI_TOKEN|circle-token.{0,10}["'"'"'][0-9a-f]{40}["'"'"']|CircleCI personal API token (circle-token prefix required)|CONTEXT:circle'

  'HIGH|vcs|JENKINS_TOKEN|jenkins.{0,30}["'"'"'][0-9a-fA-F]{32,}["'"'"']|Jenkins API token (jenkins keyword required)|CONTEXT:jenkins'

  # ---------------------------------------------------------------------------
  # Communication -- Twilio
  # ---------------------------------------------------------------------------

  'CRITICAL|communication|TWILIO_AUTH_TOKEN|twilio.{0,20}["'"'"'][0-9a-f]{32}["'"'"']|Twilio auth token (twilio keyword required)|CONTEXT:twilio'

  # ---------------------------------------------------------------------------
  # Communication -- Postmark
  # ---------------------------------------------------------------------------

  'HIGH|communication|POSTMARK_SERVER_TOKEN|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|Postmark server token UUID (postmark keyword required)|CONTEXT:postmark'

  # ---------------------------------------------------------------------------
  # AI -- Cohere, Pinecone, Voyage, Together
  # ---------------------------------------------------------------------------

  'CRITICAL|ai|COHERE_API_KEY|[0-9a-zA-Z]{40}|Cohere API key (cohere keyword must appear nearby)|CONTEXT:cohere'

  'CRITICAL|ai|PINECONE_API_KEY|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|Pinecone API key UUID (pinecone keyword required)|CONTEXT:pinecone'

  'CRITICAL|ai|VOYAGE_AI_API_KEY|pa-[0-9a-zA-Z\-_]{40,}|Voyage AI API key (voyage keyword required)|CONTEXT:voyage'

  'CRITICAL|ai|TOGETHER_AI_API_KEY|[0-9a-f]{64}|Together AI API key (together keyword required)|CONTEXT:together'

  # ---------------------------------------------------------------------------
  # Auth & Identity
  # ---------------------------------------------------------------------------

  'CRITICAL|auth|AUTH0_CLIENT_SECRET|auth0.{0,20}secret.{0,20}["'"'"'][0-9a-zA-Z\-_]{32,}["'"'"']|Auth0 client secret (auth0 keyword required)|CONTEXT:auth0'

  'CRITICAL|auth|SUPABASE_KEY|eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+|Supabase anon or service role JWT (supabase keyword required)|CONTEXT:supabase'

  # ---------------------------------------------------------------------------
  # Infrastructure
  # ---------------------------------------------------------------------------

  'HIGH|infra|CLOUDFLARE_API_KEY|[0-9a-f]{37}|Cloudflare global API key (cloudflare keyword required)|CONTEXT:cloudflare'

  'HIGH|infra|CLOUDFLARE_API_TOKEN|[A-Za-z0-9\-_]{40}|Cloudflare scoped API token (cloudflare or cf keyword required)|CONTEXT:cloudflare'

  'HIGH|infra|HEROKU_API_KEY|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|Heroku API key UUID (heroku keyword required)|CONTEXT:heroku'

  'MEDIUM|infra|VERCEL_TOKEN|[A-Za-z0-9]{24}|Vercel deploy token (vercel keyword required)|CONTEXT:vercel'

  'HIGH|infra|NETLIFY_TOKEN|[0-9a-f]{40,}|Netlify personal access token (netlify keyword required)|CONTEXT:netlify'

  # ---------------------------------------------------------------------------
  # Analytics & Monitoring
  # ---------------------------------------------------------------------------

  'HIGH|analytics|DATADOG_API_KEY|[0-9a-f]{32}|Datadog API key (datadog keyword required)|CONTEXT:datadog'

  'MEDIUM|analytics|SEGMENT_WRITE_KEY|[A-Za-z0-9]{32,}|Segment write key (segment keyword required)|CONTEXT:segment'

  'MEDIUM|analytics|MIXPANEL_TOKEN|[0-9a-f]{32}|Mixpanel project token (mixpanel keyword required)|CONTEXT:mixpanel'

  'MEDIUM|analytics|AMPLITUDE_API_KEY|[0-9a-f]{32}|Amplitude API key (amplitude keyword required)|CONTEXT:amplitude'

  # ---------------------------------------------------------------------------
  # SaaS -- Algolia
  # ---------------------------------------------------------------------------

  'CRITICAL|saas|ALGOLIA_ADMIN_KEY|[0-9a-f]{32}|Algolia admin API key (algolia keyword required)|CONTEXT:algolia'

  'MEDIUM|saas|ALGOLIA_APP_ID|[A-Z0-9]{10}|Algolia application ID (algolia keyword required)|CONTEXT:algolia'

  # ---------------------------------------------------------------------------
  # Generic -- Variable assignment patterns
  # These match common assignment forms but require the variable name as context.
  # ---------------------------------------------------------------------------

  'HIGH|generic|GENERIC_PASSWORD_ASSIGN|password[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}["'"'"']|Hardcoded password assignment (non-test file)|CONTEXT:password'

  'HIGH|generic|GENERIC_SECRET_ASSIGN|secret[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9+/=\-_]{16,}["'"'"']|Hardcoded secret assignment|CONTEXT:secret'

  'HIGH|generic|GENERIC_API_KEY_ASSIGN|api[_\-]?key[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9\-_]{16,}["'"'"']|Hardcoded API key assignment|CONTEXT:api'

  'MEDIUM|generic|GENERIC_TOKEN_ASSIGN|token[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9\-_]{20,}["'"'"']|Hardcoded token assignment|CONTEXT:token'

  'HIGH|generic|GENERIC_AUTH_ASSIGN|auth[_\-]?\(token\|key\|secret\)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{10,}["'"'"']|Hardcoded auth credential assignment|CONTEXT:auth'

  'MEDIUM|generic|AUTHORIZATION_HEADER_HARDCODED|[Aa]uthorization["'"'"'[[:space:]]*:[[:space:]]*["'"'"'][^"'"'"']{20,}["'"'"']|Hardcoded Authorization header value|CONTEXT:authorization'

)

# =============================================================================
# FILE / PATH EXCLUSIONS
# Scanner scripts should skip files whose full path matches any of these
# extended-regex patterns (checked via grep -E).
# =============================================================================

EXCLUDE_PATHS=(
  # Dependency trees -- never scan installed packages
  'node_modules'
  'vendor/'
  '\.bundle/'
  'site-packages'

  # Version control internals
  '\.git/'

  # Build and compilation output
  'dist/'
  'build/'
  'out/'
  '\.next/'
  '\.nuxt/'
  '\.svelte-kit/'
  '\.expo/'
  '__pycache__'
  '\.pyc$'
  '\.class$'

  # Minified and generated assets
  '\.min\.js$'
  '\.min\.css$'
  '\.map$'
  '\.bundle\.js$'

  # Lock files (contain registry URLs that can resemble tokens)
  'package-lock\.json$'
  'pnpm-lock\.yaml$'
  'yarn\.lock$'
  'Gemfile\.lock$'
  'Cargo\.lock$'
  'poetry\.lock$'
  'composer\.lock$'

  # Test coverage output
  'coverage/'
  '\.nyc_output'
  'lcov\.info$'

  # Test directories and files -- lower confidence for real secrets
  '/__tests__/'
  '/test/'
  '/tests/'
  '/spec/'
  '/specs/'
  '/fixtures/'
  '/mocks/'
  '/__mocks__/'
  '\.test\.ts$'
  '\.test\.tsx$'
  '\.test\.js$'
  '\.test\.jsx$'
  '\.spec\.ts$'
  '\.spec\.tsx$'
  '\.spec\.js$'
  '\.spec\.jsx$'
  '_test\.go$'
  '_spec\.rb$'

  # Documentation and changelogs
  'CHANGELOG'
  'CHANGES'

  # IDE and editor metadata
  '\.idea/'
  '\.vscode/'
  '\.DS_Store'
)

# =============================================================================
# FALSE POSITIVE PATTERNS
# If a matched line contains any of these strings, suppress the finding.
# Checked as literal substring matches (grep -F) after the primary pattern hit.
# =============================================================================

FALSE_POSITIVE_PATTERNS=(
  # Placeholder / template markers
  'YOUR_'
  'your-'
  '<your'
  'YOUR-'
  'INSERT_'
  'REPLACE_'
  'CHANGE_ME'
  'CHANGEME'
  'PLACEHOLDER'
  'placeholder'
  'PUT_YOUR'
  'PUT-YOUR'
  'ADD_YOUR'

  # Common dummy values (use longer substrings to avoid false suppression)
  'xxxxxxxxxxxx'
  'XXXXXXXXXXXX'
  'yyyyyyyyyyyy'
  'zzzzzzzzzzzz'
  'aaaaaaaaaaaa'
  '000000000000'
  'changeit'
  'changeme'

  # Documentation / example markers
  'example'
  'Example'
  'EXAMPLE'
  'sample'
  'Sample'
  'dummy'
  'Dummy'
  'fake'
  'Fake'

  # Unresolved environment variable references -- not a hardcoded secret
  'process.env.'
  'import.meta.env'
  'os.environ'
  'os.getenv'
  'getenv('
  'ENV['
  'System.getenv'

  # DI / config service lookups -- value comes from config at runtime
  'configService.'
  'config.get('
  'secrets.'
  'getSecret'
  'fetchSecret'
  'readSecret'
  'loadSecret'

  # Annotation markers that indicate the line is a comment or note
  'TODO'
  'FIXME'
  'HACK'
  'NOTE'
  'NOSONAR'

  # Vault / KMS references (value fetched at runtime)
  'vault:'
  'kms:'
  'arn:aws:kms'
  'secretsmanager'
  'parameter-store'
)

# =============================================================================
# FILE EXTENSIONS TO SCAN
# Scanner scripts should only process files whose extension appears here,
# plus filenames listed in SCAN_FILENAMES.
# =============================================================================

SCAN_EXTENSIONS=(
  # JavaScript / TypeScript ecosystem
  'ts'
  'tsx'
  'js'
  'jsx'
  'mjs'
  'cjs'
  'mts'
  'cts'

  # Python
  'py'
  'pyw'

  # Ruby
  'rb'
  'rake'
  'gemspec'

  # Go
  'go'

  # JVM
  'java'
  'kt'
  'kts'
  'scala'
  'groovy'

  # Mobile
  'swift'
  'm'
  'dart'

  # Rust
  'rs'

  # PHP
  'php'

  # C / C++
  'c'
  'cpp'
  'h'
  'hpp'

  # Config and data formats
  'json'
  'jsonc'
  'yaml'
  'yml'
  'toml'
  'ini'
  'cfg'
  'conf'
  'config'
  'properties'
  'env'

  # Shell scripts
  'sh'
  'bash'
  'zsh'
  'fish'
  'ksh'

  # Infrastructure as Code
  'tf'
  'tfvars'
  'hcl'

  # Markup and templates (sometimes contain inlined secrets)
  'xml'
  'plist'
  'html'
  'htm'
  'mustache'
  'hbs'
  'ejs'
  'njk'

  # Documentation (may contain real example keys)
  'md'
  'mdx'
  'txt'
  'rst'
  'adoc'
)

# Exact filenames (no extension) that should always be scanned
SCAN_FILENAMES=(
  'Dockerfile'
  '.env'
  '.envrc'
  'Makefile'
  'Procfile'
  'Jenkinsfile'
  'Fastfile'
  'Appfile'
  'Matchfile'
)

# Shell glob patterns for multi-part filenames
SCAN_FILENAME_GLOBS=(
  '.env.*'
  '*.env'
  'docker-compose*.yml'
  'docker-compose*.yaml'
)
