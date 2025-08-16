# Loop Food Search - Configuration and Settings Guide

## Settings Overview

Loop Food Search provides granular control over functionality through a comprehensive settings interface accessible from the main Loop Settings menu.

## Accessing Food Search Settings

1. Open **Loop** app
2. Navigate to **Settings** (gear icon)  
3. Scroll to **Food Search Settings**
4. Tap to access all food search configuration options

## Basic Settings

### Enable Food Search

**Purpose**: Master toggle for all food search functionality
**Default**: OFF (must be manually enabled)
**Impact**: When disabled, all food search features are hidden from the UI

```
Settings Path: Food Search Settings → Enable Food Search
```

**When Enabled**:
- Food search bar appears in carb entry screen
- Barcode scanner icon becomes available
- Favorite foods section is accessible
- All related UI elements are displayed

**When Disabled**:
- All food search UI elements hidden
- Existing favorite foods preserved but not accessible
- Manual carb entry remains fully functional
- No impact on existing Loop functionality

### Enable AI Analysis

**Purpose**: Controls AI-powered nutrition analysis and recommendations
**Default**: OFF (requires user activation)
**Dependency**: Requires "Enable Food Search" to be ON
**Impact**: Enables enhanced nutrition analysis and diabetes-specific recommendations

```
Settings Path: Food Search Settings → Enable AI Analysis
```

**When Enabled**:
- AI provider selection becomes available
- Enhanced nutrition analysis for all food searches
- Diabetes-specific recommendations generated
- Advanced dosing features become accessible (if also enabled)

**When Disabled**:
- Basic nutrition database lookups only
- No AI-enhanced analysis
- Limited diabetes-specific guidance
- Reduced API costs (database lookups are free)

## AI Provider Configuration

### Provider Selection

**Available Options**:
1. **OpenAI** (GPT-4o-mini)
2. **Claude** (Anthropic)  
3. **Gemini** (Google)

**Selection Criteria**:
- **Accuracy Priority**: Choose OpenAI
- **Speed Priority**: Choose Claude
- **Cost Priority**: Choose Gemini
- **Balanced**: Any provider works well

### API Key Setup

Each provider requires a valid API key:

#### OpenAI Setup
1. Visit: https://platform.openai.com/api-keys
2. Create new API key
3. Copy the key (starts with `sk-`)
4. Paste into Loop Food Search Settings
5. Tap "Test Connection" to verify

**Required Permissions**: Access to GPT-4o-mini model
**Billing**: Pay-per-use pricing (~$0.001-0.003 per food analysis)

#### Claude Setup  
1. Visit: https://console.anthropic.com/
2. Generate new API key
3. Copy the key (starts with `sk-ant-`)
4. Enter in Loop settings
5. Test connection to confirm

**Required Permissions**: Access to Claude 3 Haiku
**Billing**: Pay-per-use pricing (~$0.002-0.005 per food analysis)

#### Gemini Setup
1. Visit: https://aistudio.google.com/app/apikey
2. Create new API key  
3. Copy the key
4. Enter in Loop settings
5. Verify connection

**Required Permissions**: Gemini 1.5 Flash access
**Billing**: Pay-per-use pricing (~$0.0005-0.002 per food analysis)

### API Key Security

**Storage**: All API keys stored securely in iOS Keychain
**Access**: Keys only accessible by Loop app
**Transmission**: Keys never transmitted to Loop developers
**Rotation**: Can be changed anytime in settings
**Deletion**: Keys removed when features disabled

## Advanced Features

### Advanced Dosing Recommendations

**Purpose**: Enables research-based diabetes management guidance
**Default**: OFF (optional advanced feature)
**Dependency**: Requires both "Enable Food Search" and "Enable AI Analysis"

```
Settings Path: Food Search Settings → Advanced Dosing Recommendations
```

**Unlocked Features**:
- Fat-Protein Units (FPU) calculations
- Net carbs adjustments for fiber
- Insulin timing recommendations
- Extended dosing guidance
- Exercise impact considerations
- Dynamic absorption time analysis
- Meal size impact assessments
- Individual factor considerations
- Safety alerts and warnings

**Educational Content**:
When toggled ON, displays comprehensive explanation of FPU concept:

> "FPU stands for Fat-Protein Unit, a concept used in insulin pump therapy or advanced carbohydrate counting to account for the delayed and prolonged rise in blood glucose caused by fat and protein, which can require additional insulin dosing beyond what's needed for carbohydrates alone. Unlike carbohydrates, which have a rapid impact on blood glucose, fat and protein can cause a slower, extended rise, often starting 2–4 hours after a meal and lasting several hours."

### Voice Search

**Purpose**: Enables speech-to-text food entry
**Default**: ON (when Food Search is enabled)
**Requirements**: iOS microphone permissions

```
Settings Path: Food Search Settings → Voice Search
```

**Functionality**:
- Microphone icon appears in carb entry screen
- Converts speech to text for food search
- Supports natural language descriptions
- Integrates with AI analysis pipeline

**Privacy**: Voice data processed locally on device when possible, or sent securely to AI provider for analysis

### Camera Analysis  

**Purpose**: Enables AI vision analysis of food photos
**Default**: ON (when AI Analysis is enabled)
**Requirements**: iOS camera permissions

```
Settings Path: Food Search Settings → Camera Analysis  
```

**Functionality**:
- Camera icon appears in carb entry screen
- AI analyzes photos to identify foods
- Estimates portion sizes from visual cues
- Provides confidence scores for identification

**Privacy**: Images processed by AI provider, not stored permanently

### Barcode Scanner Priority

**Purpose**: Controls data source prioritization for barcode scans
**Default**: ON (prioritizes barcode data over text search)
**Impact**: Determines whether barcode results override text search results

```
Settings Path: Food Search Settings → Barcode Priority
```

**When Enabled**:
- Barcode scan results take precedence
- More accurate for packaged foods
- Faster results for known products

**When Disabled**:
- Text search and barcode results weighted equally
- May provide alternative nutrition data
- Useful for comparing different data sources

## Data and Privacy Settings

### Local Data Storage

**Favorite Foods Storage**: 
- Location: Local Core Data database
- Encryption: iOS standard encryption
- Backup: Included in iOS device backups
- Deletion: Removed when Food Search disabled

**Analysis Cache**:
- Duration: 24 hours for nutrition data
- Purpose: Reduce API costs and improve speed
- Scope: AI analysis results only
- Clearing: Automatic after time expiration

### External Data Sharing

**API Providers**:
- **Data Sent**: Food descriptions, search queries only
- **Data NOT Sent**: Personal health data, glucose values, therapy settings
- **Anonymization**: No user identifiers included
- **Encryption**: All communications use TLS 1.3

**Food Databases**:
- **OpenFoodFacts**: Open source nutrition database
- **USDA**: Government nutrition database  
- **Data Access**: Read-only nutrition lookups
- **Privacy**: No personal data transmitted

## Integration Settings

### Absorption Time Integration

**Default Absorption Times**: Integrates with Loop's existing absorption time presets
**AI Recommendations**: Can suggest different timing based on food analysis
**User Control**: All AI timing suggestions require manual confirmation

```
Integration Path: Loop Settings → Therapy Settings → Default Absorption Times
```

**Dynamic Absorption Time**:
- Range: 1-24 hours based on meal composition
- Visual Indicators: Shows when AI suggests different timing
- Override Capability: User can always override AI suggestions

### Carbohydrate Ratio Integration

**Existing Settings**: Works with current insulin-to-carb ratios
**No Automatic Changes**: Advanced dosing recommendations require manual review
**Clinical Guidance**: Recommendations suggest discussing changes with healthcare provider

### Favorite Foods Management

**Access Path**: Food Search Settings → Favorite Foods
**Functionality**:
- View all saved favorite foods
- Edit names and nutrition data
- Delete individual favorites
- Bulk delete all favorites
- Export favorites data

**Storage Limit**: No artificial limits (limited by device storage)
**Sync**: Local device only (no cloud sync)

## Troubleshooting Settings

### Connection Testing

**API Connection Test**:
- Available for each AI provider
- Tests authentication and connectivity
- Validates API key format
- Checks service availability

**Error Reporting**:
- In-app error messages for common issues
- Connection status indicators
- Retry mechanisms for transient failures

### Debug Information

**Usage Statistics**:
- Monthly API call counts
- Cost estimates per provider
- Success/failure rates
- Response time metrics

**Diagnostics**:
- Network connectivity status
- API endpoint accessibility
- Database connection health
- Cache performance metrics

## Migration and Backup

### Settings Backup

**iOS Backup Inclusion**: All settings included in standard iOS backups
**iCloud Sync**: Settings sync with Loop if iCloud enabled
**Manual Backup**: Export capability for settings configuration

### Data Migration

**Version Updates**: Automatic migration of settings between Loop versions
**Provider Changes**: Easy switching between AI providers
**Feature Deprecation**: Graceful handling of discontinued features

### Reset Options

**Reset All Food Search Settings**: Returns all settings to defaults
**Clear Favorites**: Removes all saved favorite foods
**Clear Cache**: Removes all cached analysis results
**Reset API Keys**: Clears all stored provider credentials

## Performance Settings

### Cache Management

**Cache Size Limit**: Configurable maximum cache size
**Cache Duration**: Adjustable expiration times
**Cache Clearing**: Manual and automatic clearing options

### Network Optimization

**Request Timeout**: Configurable timeout for API calls
**Retry Logic**: Number of retry attempts for failed requests
**Offline Mode**: Behavior when network unavailable

### Battery Optimization

**Background Processing**: Controls for background analysis
**Power Management**: Reduced functionality in low power mode
**Resource Usage**: Monitoring of CPU and memory usage

## Accessibility Settings

### VoiceOver Support

**Screen Reader**: Full VoiceOver compatibility
**Voice Navigation**: Voice control support
**Text Scaling**: Dynamic text size support

### Visual Accessibility

**High Contrast**: Enhanced visual contrast options
**Color Accessibility**: Colorblind-friendly alternatives
**Large Text**: Support for iOS accessibility text sizes

### Motor Accessibility

**Switch Control**: Compatible with iOS Switch Control
**Voice Control**: iOS Voice Control integration
**Simplified Interface**: Reduced complexity options

---

*This configuration guide covers all available settings for Loop Food Search v2.0+. Settings may vary based on iOS version and device capabilities.*