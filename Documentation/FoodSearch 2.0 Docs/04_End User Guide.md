# Loop Food Search - End User Guide

## Overview

Loop's Food Search feature uses AI analysis to provide accurate nutrition information and advanced diabetes management recommendations. This guide explains how to set up, use, and understand the food search functionality.

## Quick Setup

### 1. Enable Food Search
1. Open Loop Settings
2. Navigate to **Food Search Settings**
3. Toggle **"Enable Food Search"** to ON
4. The feature is now active and ready to use

### 2. Configure AI Analysis (Recommended)
1. In **Food Search Settings**, toggle **"Enable AI Analysis"** to ON
2. Choose your preferred AI provider:
   - **OpenAI** (GPT-4o-mini) - Most accurate, ~$0.001-0.003 per analysis
   - **Claude** (Anthropic) - Fast and reliable, ~$0.002-0.005 per analysis  
   - **Gemini** (Google) - Cost-effective, ~$0.0005-0.002 per analysis
3. Enter your API key for the selected provider
4. Test the connection using the "Test API Connection" button

### 3. Enable Advanced Dosing (Optional)
1. In **Food Search Settings**, toggle **"Advanced Dosing Recommendations"** to ON
2. This unlocks research-based guidance on:
   - Fat-Protein Units (FPU) calculations
   - Fiber impact analysis
   - Exercise considerations
   - Dynamic absorption timing
   - Extended dosing strategies

## How to Use Food Search

### Adding Food Entries

#### Method 1: Text Search
1. Tap **"Add Carb Entry"** in Loop
2. In the search bar, type the food name (e.g., "apple pie")
3. Select from the suggested results
4. The AI will analyze and provide detailed nutrition information

#### Method 2: Barcode Scanner
1. Tap the **barcode icon** in the carb entry screen
2. Point your camera at the product barcode
3. Loop automatically fetches product details from our food database
4. AI analysis provides enhanced nutrition breakdown

#### Method 3: Camera Analysis (AI Vision)
1. Tap the **camera icon** in the carb entry screen
2. Take a photo of your meal or food
3. The AI analyzes the image to identify foods and estimate portions
4. Review and confirm the AI's assessment

#### Method 4: Voice Search
1. Tap the **microphone icon** in the carb entry screen
2. Describe your meal (e.g., "Large slice of cheese pizza")
3. The AI converts speech to text and analyzes the food
4. Confirm the results and adjust as needed

### Understanding the Results

#### Nutrition Circles
The colorful circles show key macronutrients per serving:
- **Blue Circle**: Carbohydrates (grams)
- **Green Circle**: Calories (kcal)
- **Yellow Circle**: Fat (grams)  
- **Purple Circle**: Fiber (grams)
- **Red Circle**: Protein (grams)

Each circle fills based on typical portion sizes for that nutrient.

#### Food Details Section
Expandable section showing:
- Complete ingredient breakdown
- Individual nutrition values per component
- Cooking methods and preparation details

#### Diabetes Considerations
AI-generated notes about:
- Blood glucose impact predictions
- Absorption timing recommendations
- Special considerations for the specific food

### Advanced Dosing Features

When **Advanced Dosing Recommendations** is enabled, you'll see an expandable **"Advanced Analysis"** section with up to 9 specialized insights:

#### Fat-Protein Units (FPU)
- Calculates additional insulin needs for high-fat/protein meals
- Provides extended dosing timing recommendations
- Based on peer-reviewed diabetes research

#### Fiber Impact Analysis  
- Shows how fiber content affects carb absorption
- Suggests net carb adjustments when appropriate
- Explains timing implications for blood glucose

#### Exercise Considerations
- Guidance on pre/post-workout meal timing
- Recommendations for different activity levels
- Blood glucose management during exercise

#### Dynamic Absorption Timing
- Customized absorption time recommendations (1-24 hours)
- Based on meal composition, fat content, and fiber
- Visual indicators when timing differs from defaults

#### Extended Dosing Strategies
- Dual-wave or square-wave bolus recommendations
- Specific timing for high-fat or complex meals
- Evidence-based dosing patterns

#### Individual Factors
- Personal considerations based on meal patterns
- Customization suggestions for your diabetes management
- Integration with your existing therapy settings

#### Safety Alerts
- Important warnings about blood glucose risks
- Medication interaction considerations
- When to consult your healthcare provider

### Favorite Foods

#### Saving Favorites
1. After analyzing a food, tap **"Add to Favorites"**
2. Give it a memorable name
3. The food saves with all nutrition data and AI analysis
4. Access from the **Favorite Foods** section in settings

#### Using Favorites
1. In the carb entry screen, your favorites appear at the top
2. Tap any favorite to instantly load its nutrition data  
3. Adjust servings as needed
4. Edit or delete favorites in Food Search Settings

### Portion and Serving Management

#### Adjusting Servings
- Use the **serving stepper** or **number input** to change quantity
- All nutrition values automatically update
- AI analysis scales proportionally

#### Understanding Serving Sizes
- **Standard servings**: Based on USDA food database standards
- **Visual estimates**: AI provides size comparisons (e.g., "palm-sized")
- **Weight measures**: Grams, ounces, or other units when available
- **Volume measures**: Cups, tablespoons, etc. for liquids

## API Costs and Usage

### Estimated Costs Per Food Analysis

The actual cost depends on meal complexity and analysis depth:

#### OpenAI (GPT-4o-mini) - Most Accurate
- **Simple foods**: ~$0.001 (apple, banana, bread slice)
- **Complex meals**: ~$0.003 (casseroles, mixed dishes)
- **Monthly estimate**: $3-10 for typical users (100-300 analyses)

#### Claude (Anthropic) - Fast & Reliable  
- **Simple foods**: ~$0.002
- **Complex meals**: ~$0.005
- **Monthly estimate**: $6-15 for typical users

#### Gemini (Google) - Most Cost-Effective
- **Simple foods**: ~$0.0005  
- **Complex meals**: ~$0.002
- **Monthly estimate**: $1.50-6 for typical users

### Usage Tips to Manage Costs
1. **Use Favorites**: Save frequently eaten foods to avoid re-analysis
2. **Batch similar foods**: Analyze meal components together when possible
3. **Choose appropriate provider**: Gemini for cost-consciousness, OpenAI for accuracy
4. **Monitor usage**: Check your API provider's usage dashboard monthly

### Free Analysis Options
- **Barcode scanner**: Uses free food database lookups (no AI cost)
- **Manual entry**: Direct nutrition input (no AI needed)
- **Cached results**: Previously analyzed foods don't require new API calls

## Settings and Configuration

### Food Search Settings

#### Basic Settings
- **Enable Food Search**: Master toggle for all functionality
- **Enable AI Analysis**: Toggle for AI-powered nutrition analysis
- **AI Provider**: Choose between OpenAI, Claude, or Gemini
- **API Keys**: Secure storage for your provider credentials

#### Advanced Settings
- **Advanced Dosing Recommendations**: Enable FPU and research-based guidance
- **Voice Search**: Enable speech-to-text food entry
- **Camera Analysis**: Enable AI vision for food photos
- **Barcode Priority**: Prioritize barcode results over text search

#### Privacy Settings
- **Data Storage**: All analysis results stored locally on device
- **API Communication**: Only nutrition queries sent to AI providers
- **No Personal Data**: No personal health information shared externally

### Integration with Loop Settings

#### Absorption Time Integration
- AI recommendations integrate with your existing absorption time presets
- Custom absorption times saved and reused for similar foods
- Visual indicators when AI suggests timing different from defaults

#### Carb Ratio Integration  
- Works with your existing insulin-to-carb ratios
- Advanced dosing recommendations factor in your current therapy settings
- No automatic dosing changes - all recommendations require your review

## Troubleshooting

### Common Issues

#### "No Results Found"
- Try different search terms or simpler food names
- Check internet connection for database access
- Consider using barcode scanner for packaged foods

#### "API Error" Messages
- Verify API key is correctly entered in settings
- Check API provider's service status
- Ensure sufficient API credits in your account

#### Nutrition Values Seem Incorrect
- Remember values are estimates based on typical preparations
- Complex or restaurant foods may have higher variability
- Always use clinical judgment and adjust based on your experience

#### Advanced Dosing Not Showing
- Ensure "Advanced Dosing Recommendations" is enabled in settings
- Feature requires AI Analysis to be active
- Some simple foods may not trigger advanced analysis

### Getting Help

#### In-App Support
- Tap the **"?"** icon in Food Search settings
- Review example searches and usage tips
- Check API connection status

#### Healthcare Provider Guidance
- Share this guide with your diabetes care team
- Discuss integration with your current therapy
- Review any advanced dosing recommendations before implementing

#### Technical Support
- Report issues through Loop's standard support channels
- Include specific error messages when possible
- Mention which AI provider you're using

## Best Practices

### For Accurate Results
1. **Be specific**: "Grilled chicken breast" vs. just "chicken"
2. **Include cooking method**: Baked, fried, grilled, steamed, etc.
3. **Specify portions**: Use visual estimates or weights when possible
4. **Review AI suggestions**: Always verify recommendations make sense

### For Cost Management  
1. **Save frequently eaten foods** as favorites
2. **Use barcode scanner** for packaged items when possible
3. **Start with simpler AI provider** (Gemini) and upgrade if needed
4. **Monitor monthly usage** through your API provider dashboard

### For Diabetes Management
1. **Start conservatively** with AI dosing recommendations
2. **Track outcomes** and adjust based on your glucose patterns
3. **Discuss with healthcare team** before making therapy changes
4. **Keep food diary** to identify patterns and preferences

## Privacy and Security

### Data Protection
- **Local Storage**: All food analysis results stored only on your device
- **No Health Data Sharing**: Personal diabetes information never sent to AI providers
- **Secure API Communication**: All queries encrypted and anonymized
- **User Control**: Delete food history or disable features at any time

### API Key Security
- Keys stored securely in iOS Keychain
- Never logged or transmitted to Loop developers
- You maintain full control of your API accounts
- Can revoke or rotate keys at any time

## Updates and New Features

Loop's Food Search functionality is actively developed with regular improvements:

- **Database Updates**: Food database refreshed monthly
- **AI Model Improvements**: Providers regularly enhance their analysis capabilities  
- **New Food Sources**: Additional barcode databases and nutrition sources
- **Advanced Features**: Ongoing research integration and clinical feature development

Stay updated through Loop's standard release channels for the latest enhancements and features.

---

*This guide covers Loop Food Search v2.0+. For questions or feedback, please use Loop's community support channels.*