# Loop Food Search - Troubleshooting Guide

## Common Issues and Solutions

This guide helps resolve the most frequently encountered issues with Loop's Food Search functionality.

## Setup and Configuration Issues

### "Food Search Not Available"

**Symptoms**:
- Food search options not visible in carb entry screen
- Settings menu missing Food Search section

**Causes & Solutions**:

1. **Food Search Disabled**
   - **Check**: Settings → Food Search Settings → Enable Food Search
   - **Solution**: Toggle "Enable Food Search" to ON
   - **Result**: Food search UI elements will appear immediately

2. **App Version Too Old**
   - **Check**: Loop app version in Settings → About
   - **Solution**: Update to Loop v2.0+ that includes Food Search
   - **Result**: Food Search settings will appear after update

3. **iOS Compatibility**
   - **Check**: Device running iOS 14+ required
   - **Solution**: Update iOS to supported version
   - **Result**: Full Food Search functionality available

### "AI Analysis Not Working"

**Symptoms**:
- Food searches return basic data only
- No diabetes-specific recommendations
- Missing advanced analysis features

**Troubleshooting Steps**:

1. **Verify AI Analysis Enabled**
   ```
   Settings → Food Search Settings → Enable AI Analysis → ON
   ```

2. **Check AI Provider Selection**
   - Ensure one of OpenAI, Claude, or Gemini is selected
   - Provider selection must be completed

3. **Validate API Key**
   - Tap "Test API Connection" for your selected provider
   - Green checkmark indicates successful connection
   - Red X indicates configuration problem

4. **API Key Common Issues**:
   - **OpenAI**: Key must start with `sk-` and have GPT-4o-mini access
   - **Claude**: Key must start with `sk-ant-` with Claude 3 access
   - **Gemini**: Key must have Gemini 1.5 Flash permissions

## API Connection Issues

### "API Authentication Failed"

**Error Messages**:
- "Invalid API key"
- "Authentication error"  
- "Unauthorized access"

**Solutions**:

1. **Verify API Key Format**:
   - **OpenAI**: `sk-...` (51 characters total)
   - **Claude**: `sk-ant-...` (varies)
   - **Gemini**: Usually 30+ characters

2. **Check API Key Permissions**:
   - **OpenAI**: Ensure billing setup and GPT-4o-mini access
   - **Claude**: Verify Claude 3 Haiku model access
   - **Gemini**: Confirm Gemini 1.5 Flash enabled

3. **Generate New API Key**:
   - Visit your provider's console
   - Generate fresh API key
   - Replace old key in Loop settings
   - Test connection again

### "API Quota Exceeded"

**Error Messages**:
- "Rate limit exceeded"
- "Quota exceeded"
- "Usage limit reached"

**Solutions**:

1. **Check Usage Dashboard**:
   - **OpenAI**: https://platform.openai.com/usage
   - **Claude**: https://console.anthropic.com/
   - **Gemini**: https://console.cloud.google.com/

2. **Increase Limits**:
   - Add billing information to provider account
   - Increase spending limits if needed
   - Wait for quota reset (usually monthly)

3. **Optimize Usage**:
   - Use favorite foods to avoid re-analysis
   - Switch to more cost-effective provider (Gemini)
   - Enable barcode scanner for packaged foods (no API cost)

### "Network Connection Failed"

**Error Messages**:
- "Network unavailable"
- "Connection timeout"
- "Request failed"

**Troubleshooting**:

1. **Check Internet Connection**:
   - Verify WiFi or cellular data active
   - Test other apps requiring internet
   - Try switching between WiFi and cellular

2. **Check Provider Status**:
   - **OpenAI**: https://status.openai.com/
   - **Claude**: https://status.anthropic.com/
   - **Gemini**: https://status.cloud.google.com/

3. **Restart Network Connection**:
   - Turn airplane mode ON, wait 10 seconds, turn OFF
   - Reset network settings if persistent issues
   - Restart device if network problems continue

## Search and Results Issues

### "No Results Found"

**Symptoms**:
- Search returns empty results
- "No food found" message appears
- Search suggestions don't appear

**Solutions**:

1. **Try Different Search Terms**:
   - **Instead of**: "pizza"
   - **Try**: "cheese pizza slice", "pepperoni pizza"
   - **Include**: Cooking method, brand name, preparation style

2. **Use Specific Descriptions**:
   - **Better**: "grilled chicken breast, skinless"
   - **Worse**: "chicken"
   - **Include**: Size, preparation, ingredients

3. **Alternative Search Methods**:
   - **Barcode Scanner**: For packaged foods
   - **Voice Search**: Natural language descriptions
   - **Camera Analysis**: Take photo of food

4. **Check Network Connection**:
   - Food database requires internet access
   - Verify connection working in other apps
   - Try again after network issues resolved

### "Inaccurate Nutrition Information"

**Symptoms**:
- Nutrition values seem too high/low
- Unexpected carbohydrate counts
- Missing macronutrients

**Understanding & Solutions**:

1. **Nutrition Data Variability**:
   - Restaurant vs. homemade preparations differ significantly
   - Generic items averaged across brands/preparations
   - AI makes reasonable assumptions for missing data

2. **Verify Serving Sizes**:
   - Check if serving size matches your portion
   - Adjust serving multiplier as needed
   - Pay attention to weight vs. volume measurements

3. **Cross-Reference Sources**:
   - Use barcode scanner for packaged foods (most accurate)
   - Compare with nutrition labels when available
   - Consider food preparation differences

4. **Provide Better Descriptions**:
   - Include cooking method (baked, fried, grilled)
   - Specify ingredients (whole wheat bread vs. white bread)
   - Mention brands for processed foods

### "Advanced Analysis Missing"

**Symptoms**:
- No "Advanced Analysis" section visible
- Missing FPU calculations
- No extended dosing recommendations

**Requirements Check**:

1. **Enable Advanced Features**:
   ```
   Settings → Food Search Settings → Advanced Dosing Recommendations → ON
   ```

2. **Verify Dependencies**:
   - "Enable Food Search" must be ON
   - "Enable AI Analysis" must be ON
   - Valid AI provider configured

3. **Food Complexity**:
   - Simple foods (apple, water) may not trigger advanced analysis
   - Complex meals (casseroles, mixed dishes) more likely to show advanced features
   - High fat/protein foods typically generate FPU calculations

## Barcode Scanner Issues

### "Barcode Not Recognized"

**Symptoms**:
- Scanner doesn't detect barcode
- "Barcode not found" message
- Scanner doesn't activate

**Solutions**:

1. **Improve Scanning Conditions**:
   - Ensure good lighting (avoid shadows)
   - Hold device steady, 6-8 inches from barcode
   - Clean camera lens if blurry
   - Try different angles if barcode curved/damaged

2. **Barcode Format Issues**:
   - Most common: UPC, EAN, Code 128
   - Some specialty codes not supported
   - Try typing product name if barcode fails

3. **Camera Permissions**:
   - Check: Settings → Privacy → Camera → Loop → ON
   - Restart app after enabling permissions
   - Reboot device if permissions not working

### "Product Not Found in Database"

**Symptoms**:
- Barcode scans successfully but no product data
- "Product not available" message

**Solutions**:

1. **Database Coverage**:
   - OpenFoodFacts covers ~2 million products worldwide
   - Local/regional products may not be included
   - New products take time to be added

2. **Alternative Approaches**:
   - Try text search with product name
   - Use nutrition label for manual entry
   - Take photo with camera analysis feature

3. **Contribute to Database** (Optional):
   - Visit OpenFoodFacts.org to add missing products
   - Helps improve database for all users

## Voice Search Issues

### "Voice Not Recognized"

**Symptoms**:
- Microphone icon doesn't respond
- No speech-to-text conversion
- Voice search not available

**Troubleshooting**:

1. **Check Microphone Permissions**:
   - Settings → Privacy → Microphone → Loop → ON
   - Restart app after enabling permissions

2. **Test Microphone**:
   - Try voice memos or Siri to test microphone
   - Ensure microphone not blocked or damaged
   - Remove case if covering microphone

3. **Speech Recognition**:
   - Speak clearly and at moderate pace
   - Use quiet environment (minimize background noise)
   - Try shorter, simpler descriptions first

### "Voice Commands Not Understood"

**Symptoms**:
- Speech converted to text but no food found
- Unusual text interpretation

**Optimization Tips**:

1. **Clear Speech Patterns**:
   - **Good**: "Large slice of pepperoni pizza"
   - **Avoid**: "Um, like, you know, some pizza thing"
   - Speak in complete phrases

2. **Structured Descriptions**:
   - Include quantity: "Two cups of", "One medium"
   - Include preparation: "Baked chicken breast"
   - Include key ingredients: "Caesar salad with dressing"

## Camera Analysis Issues

### "Photo Analysis Failed"

**Symptoms**:
- Camera takes photo but no analysis results
- "Unable to identify food" message
- Analysis takes very long time

**Solutions**:

1. **Improve Photo Quality**:
   - Ensure good lighting (natural light best)
   - Focus clearly on food items
   - Include scale references (plate, utensils)
   - Avoid cluttered backgrounds

2. **Optimal Food Positioning**:
   - Center food items in frame
   - Show full portions, not just parts
   - Separate distinct food items when possible
   - Avoid overlapping foods

3. **AI Provider Performance**:
   - Different providers have varying vision capabilities
   - Try switching providers if analysis consistently fails
   - OpenAI typically has strongest vision analysis

### "Inaccurate Photo Identification"

**Symptoms**:
- AI identifies wrong foods
- Portion estimates way off
- Missing food items in photo

**Improvement Strategies**:

1. **Better Photo Composition**:
   - Clear view of all food items
   - Standard plate/bowl sizes for scale reference
   - Good contrast between food and background
   - Multiple angles for complex dishes

2. **Manual Corrections**:
   - Review AI identification before confirming
   - Adjust portion sizes based on your knowledge
   - Add missed items manually

3. **Hybrid Approach**:
   - Use photo analysis as starting point
   - Refine with text search for specific items
   - Combine with voice description for clarity

## Performance Issues

### "Slow Response Times"

**Symptoms**:
- Long delays for search results
- App freezing during analysis
- Timeout errors

**Optimization**:

1. **Network Performance**:
   - Try switching between WiFi and cellular
   - Close other bandwidth-intensive apps
   - Wait for better network conditions

2. **Provider Performance**:
   - **Fastest**: Usually Gemini
   - **Balanced**: Claude  
   - **Comprehensive**: OpenAI (may be slower)

3. **Device Performance**:
   - Close unnecessary background apps
   - Restart app if memory issues
   - Reboot device if persistent slowness

### "App Crashes During Food Search"

**Symptoms**:
- App closes unexpectedly during search
- Consistent crashes on specific foods
- Memory-related crashes

**Solutions**:

1. **Memory Management**:
   - Close other memory-intensive apps
   - Restart Loop app
   - Reboot device to clear memory

2. **Clear Cache**:
   - Settings → Food Search Settings → Clear Cache
   - Removes stored analysis results
   - Frees up storage space

3. **Update App**:
   - Check App Store for Loop updates
   - Bug fixes often resolve crash issues
   - Backup settings before updating

## Advanced Feature Issues

### "FPU Calculations Missing"

**Symptoms**:
- High fat/protein foods don't show FPU analysis
- Advanced dosing recommendations incomplete

**Troubleshooting**:

1. **Verify Settings**:
   ```
   Advanced Dosing Recommendations → ON
   AI Analysis → ON
   Valid API Provider configured
   ```

2. **Food Requirements**:
   - Foods must have significant fat/protein content
   - Complex meals more likely to trigger FPU calculations
   - Simple carbohydrates may not need FPU analysis

3. **Provider Capabilities**:
   - All providers support FPU calculations
   - Quality may vary between providers
   - Try different provider if calculations seem inaccurate

### "Absorption Time Recommendations Not Applied"

**Symptoms**:
- AI suggests different absorption time but not applied
- Absorption time stays at default value

**Understanding**:

1. **Manual Confirmation Required**:
   - AI recommendations are suggestions only
   - User must manually select recommended absorption time
   - Safety feature to prevent automatic therapy changes

2. **Integration Process**:
   - Review AI recommendation in Advanced Analysis
   - Tap absorption time field to change if desired
   - AI reasoning provided for transparency

## Data and Privacy Concerns

### "API Key Security"

**Concerns**:
- Are API keys secure?
- Can others access my keys?
- What if keys are compromised?

**Security Measures**:

1. **Secure Storage**:
   - Keys stored in iOS Keychain (most secure method)
   - Never transmitted to Loop developers
   - Encrypted on device

2. **Key Rotation**:
   - Change keys anytime in settings
   - Revoke old keys at provider console
   - Generate new keys as needed

3. **Compromise Response**:
   - Immediately revoke compromised key at provider
   - Generate new key and update in Loop
   - Monitor usage for unauthorized activity

### "Data Privacy Questions"

**Concerns**:
- What data is sent to AI providers?
- Is personal health information shared?
- Can providers identify me?

**Privacy Practices**:

1. **Data Sent to Providers**:
   - Food descriptions only
   - No personal identifiers
   - No glucose values or therapy settings
   - No location data

2. **Data NOT Sent**:
   - Personal health information
   - Glucose readings
   - Insulin dosing information
   - Device identifiers

3. **Anonymization**:
   - All queries anonymized
   - No way to link requests to individuals
   - Providers cannot build user profiles

## Getting Additional Help

### In-App Resources

1. **Help Section**:
   - Food Search Settings → Help
   - Example searches and tips
   - Common troubleshooting steps

2. **Connection Testing**:
   - Test API connections directly
   - Validate configuration
   - Check service status

### Community Support

1. **Loop Community**:
   - Facebook groups and forums
   - User-to-user troubleshooting
   - Share tips and experiences

2. **Documentation**:
   - Complete user guides
   - Technical implementation details
   - Configuration examples

### Professional Support

1. **Healthcare Provider**:
   - Discuss diabetes management recommendations
   - Review advanced dosing suggestions
   - Integrate with existing therapy

2. **Technical Issues**:
   - Report persistent bugs
   - Request new features
   - Share feedback on functionality

### Emergency Situations

**Important**: Food Search is a tool to assist diabetes management, not replace medical judgment.

**If Experiencing**:
- Unexpected blood glucose patterns
- Questions about AI dosing recommendations
- Concerns about food analysis accuracy

**Actions**:
- Consult healthcare provider immediately
- Use traditional carb counting methods as backup
- Don't rely solely on AI recommendations for critical decisions

---

*This troubleshooting guide covers common issues with Loop Food Search v2.0+. For persistent issues not covered here, consult with your healthcare provider or Loop community support channels.*