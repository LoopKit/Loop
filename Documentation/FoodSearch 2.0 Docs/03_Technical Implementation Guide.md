# Loop Food Search - Technical Implementation Guide

## Architecture Overview

Loop's Food Search system integrates multiple data sources and AI providers to deliver comprehensive nutrition analysis and advanced diabetes management recommendations.

### Core Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   UI Layer      │    │  Service Layer   │    │  Data Sources   │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ CarbEntryView   │───▶│ FoodSearchRouter │───▶│ OpenFoodFacts   │
│ FoodSearchBar   │    │ AIFoodAnalysis   │    │ USDA Database   │
│ BarcodeScan     │    │ VoiceSearch      │    │ Custom DB       │
│ AICameraView    │    │ BarcodeService   │    └─────────────────┘
└─────────────────┘    └──────────────────┘              │
                                  │                      │
                       ┌──────────────────┐              │
                       │   AI Providers   │              │
                       ├──────────────────┤              │
                       │ OpenAI-GPT       │◀─────────────┘
                       │ Claude-Anthropic │
                       │ Gemini-Google    │
                       └──────────────────┘
```

## Service Layer Implementation

### FoodSearchRouter

**File**: `Services/FoodSearchRouter.swift`

Manages routing between different food data sources:

```swift
class FoodSearchRouter {
    // Primary route: Barcode → OpenFoodFacts → AI Analysis
    // Secondary route: Text Search → USDA DB → AI Analysis  
    // Tertiary route: Voice/Camera → AI Direct Analysis
}
```

**Key Features**:
- Intelligent source selection based on input type
- Fallback mechanisms for data source failures
- Caching layer for frequently accessed foods
- Rate limiting for API calls

### AIFoodAnalysis

**File**: `Services/AIFoodAnalysis.swift`

Core AI integration service supporting multiple providers:

```swift
struct AIFoodAnalysisResult {
    // Basic nutrition
    let carbohydrates: Double
    let calories: Double?
    let fat: Double?
    // ... basic fields
    
    // Advanced dosing fields (10 new fields)
    let fatProteinUnits: String?
    let netCarbsAdjustment: String?
    let insulinTimingRecommendations: String?
    let fpuDosingGuidance: String?
    let exerciseConsiderations: String?
    let absorptionTimeReasoning: String?
    let mealSizeImpact: String?
    let individualizationFactors: String?
    let safetyAlerts: String?
}
```

## Data Models

### OpenFoodFactsModels

**File**: `Models/OpenFoodFactsModels.swift`

Comprehensive nutrition data structure:

```swift
struct OpenFoodFactsProduct {
    let productName: String?
    let brands: String?
    let nutriments: Nutriments
    let imageUrl: String?
    let servingSize: String?
    let dataSource: DataSource
    
    // Calculated properties
    var carbsPerServing: Double? { ... }
    var caloriesPerServing: Double? { ... }
    // ... additional computed properties
}
```

### FoodItemAnalysis

Advanced food component breakdown:

```swift
struct FoodItemAnalysis {
    let name: String
    let quantity: String
    let carbs: Double
    let calories: Double?
    let preparationMethod: String?
    let confidence: String?
}
```

## AI Provider Integration

### OpenAI Integration

**Endpoint**: `https://api.openai.com/v1/chat/completions`
**Model**: `gpt-4o-mini`
**Cost**: ~$0.001-0.003 per analysis

```swift
struct OpenAIRequest {
    let model = "gpt-4o-mini"
    let messages: [ChatMessage]
    let temperature = 0.3
    let max_tokens = 1500
}
```

### Claude Integration

**Endpoint**: `https://api.anthropic.com/v1/messages`
**Model**: `claude-3-haiku-20240307`
**Cost**: ~$0.002-0.005 per analysis

```swift
struct ClaudeRequest {
    let model = "claude-3-haiku-20240307"
    let max_tokens = 1500
    let messages: [ClaudeMessage]
}
```

### Gemini Integration

**Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent`
**Model**: `gemini-1.5-flash`
**Cost**: ~$0.0005-0.002 per analysis

```swift
struct GeminiRequest {
    let contents: [GeminiContent]
    let generationConfig: GeminiConfig
}
```

## Advanced Dosing System

### Research Integration

The Advanced Dosing Recommendations feature incorporates peer-reviewed research:

1. **Fat-Protein Units (FPU)**: Based on Warsaw study methodology
2. **Exercise Impact**: Derived from Diabetes Care journal guidelines
3. **Fiber Analysis**: USDA fiber impact research
4. **Absorption Timing**: Clinical diabetes management studies

### Implementation Details

**Conditional Display Logic**:
```swift
if UserDefaults.standard.advancedDosingRecommendationsEnabled {
    advancedAnalysisSection(aiResult: aiResult)
}
```

**Progressive Disclosure UI**:
- Collapsible "Advanced Analysis" section
- 9 expandable subsections for different aspects
- Dynamic content based on food type and complexity

## UI Implementation

### CarbEntryView Architecture

**File**: `Views/CarbEntryView.swift`

**Key Components**:
1. **Nutrition Circles**: Horizontal scrollable macronutrient display
2. **Food Details**: Expandable ingredient breakdown
3. **Advanced Analysis**: Collapsible section with 9 subsections
4. **Settings Integration**: Dynamic feature toggling

**Circle Implementation**:
```swift
struct NutritionCircle: View {
    // 64pt diameter circles with animated progress
    // 4pt stroke width for prominence
    // Center-aligned in scrollable container
}
```

### Settings Integration

**File**: `Views/AISettingsView.swift`

**Advanced Dosing Toggle**:
```swift
Section(header: Text("Advanced Features")) {
    Toggle("Advanced Dosing Recommendations", 
           isOn: $isAdvancedDosingEnabled)
    
    if isAdvancedDosingEnabled {
        Text("FPU stands for Fat-Protein Unit...")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

## Data Flow

### Standard Food Analysis Flow

```
1. User Input (text/barcode/voice/camera)
2. FoodSearchRouter determines data source
3. Primary data fetch (OpenFoodFacts/USDA)
4. AIFoodAnalysis enhances with provider
5. Parse and structure response
6. Update UI with nutrition circles and details
7. Cache result for future use
```

### Advanced Dosing Flow

```
1. Check UserDefaults.advancedDosingRecommendationsEnabled
2. If enabled, use advanced AI prompts
3. Parse 10 additional analysis fields
4. Display in collapsible Advanced Analysis section
5. Progressive disclosure of 9 subsections
6. Dynamic absorption time integration
```

## Error Handling

### API Error Management

```swift
enum FoodSearchError: Error {
    case networkUnavailable
    case apiKeyInvalid
    case quotaExceeded
    case invalidResponse
    case noResultsFound
}
```

**Error Recovery**:
1. **Network Issues**: Cached results, offline mode
2. **API Failures**: Provider fallback (OpenAI → Claude → Gemini)
3. **Invalid Keys**: Clear UI messaging, settings redirect
4. **Rate Limits**: Queue requests, user notification

### Data Validation

```swift
func validateNutritionData(_ product: OpenFoodFactsProduct) -> Bool {
    guard product.nutriments.carbohydrates >= 0,
          product.nutriments.carbohydrates <= 100 else { return false }
    // Additional validation rules...
}
```

## Performance Optimization

### Caching Strategy

1. **Local Storage**: Core Data for favorite foods
2. **Memory Cache**: Recent searches and AI results
3. **Image Caching**: Product images with expiration
4. **API Response Cache**: 24-hour TTL for stable data

### Network Optimization

```swift
// Request batching for multiple foods
func batchAnalyzeFeods(_ foods: [String]) async -> [AIFoodAnalysisResult] {
    // Combine up to 3 foods per API call
    // Reduces cost and improves performance
}
```

### UI Performance

- **Lazy Loading**: Nutrition circles with on-demand rendering
- **View Recycling**: Reusable components for food items
- **Animation Optimization**: Hardware-accelerated progress animations

## Security Implementation

### API Key Management

```swift
extension Keychain {
    static func storeAPIKey(_ key: String, for provider: AIProvider) {
        // Secure storage in iOS Keychain
        // Keys never logged or transmitted to Loop servers
    }
}
```

### Data Privacy

1. **Local Processing**: All personal data stays on device
2. **Anonymized Queries**: No personal identifiers sent to AI
3. **Encrypted Communication**: TLS 1.3 for all API calls
4. **User Control**: Complete data deletion capability

## Testing Framework

### Unit Tests

**File**: `LoopTests/FoodSearchIntegrationTests.swift`

```swift
class FoodSearchIntegrationTests: XCTestCase {
    func testOpenFoodFactsIntegration() { ... }
    func testAIProviderFallback() { ... }
    func testAdvancedDosingLogic() { ... }
    func testNutritionCircleCalculations() { ... }
}
```

### Mock Services

```swift
class MockAIFoodAnalysis: AIFoodAnalysisService {
    // Predictable responses for testing
    // No actual API calls during tests
    // Validation of request formatting
}
```

## Deployment Considerations

### Feature Flags

```swift
struct FeatureFlags {
    static let advancedDosingEnabled = true
    static let voiceSearchEnabled = true
    static let cameraAnalysisEnabled = true
}
```

### Gradual Rollout

1. **Phase 1**: Basic food search and barcode scanning
2. **Phase 2**: AI analysis with basic recommendations  
3. **Phase 3**: Advanced dosing recommendations
4. **Phase 4**: Voice and camera analysis

### Monitoring

```swift
// Analytics integration for usage patterns
AnalyticsService.track("food_search_used", 
                      provider: currentProvider,
                      resultCount: results.count)
```

## API Cost Management

### Usage Tracking

```swift
class APIUsageTracker {
    private var monthlyUsage: [AIProvider: Int] = [:]
    
    func recordUsage(provider: AIProvider, tokens: Int) {
        // Track monthly usage per provider
        // Alert users approaching limits
    }
}
```

### Cost Optimization

1. **Request Batching**: Multiple foods per API call when possible
2. **Smart Caching**: Avoid redundant analyses
3. **Provider Selection**: Route based on cost/accuracy preferences
4. **Fallback Strategy**: Graceful degradation when limits reached

## Future Enhancements

### Planned Features

1. **Meal Planning**: AI-powered meal suggestions
2. **Recipe Analysis**: Complete recipe nutrition breakdown
3. **Restaurant Integration**: Chain restaurant menu analysis
4. **Nutritionist Chat**: AI-powered nutrition counseling
5. **Clinical Integration**: Healthcare provider data sharing

### Technical Roadmap

1. **Performance**: Core ML models for offline analysis
2. **Accuracy**: Custom-trained models for diabetes management
3. **Integration**: HealthKit nutrition data synchronization
4. **Intelligence**: Personalized recommendations based on glucose patterns

---

*This technical guide covers the implementation details for Loop Food Search v2.0+. For development questions, consult the codebase and integration tests.*
