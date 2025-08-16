# Loop Food Search Documentation

## Overview

This directory contains comprehensive documentation for Loop's Food Search functionality, including AI-powered nutrition analysis and advanced diabetes management recommendations.

## Documentation Structure

### 📋 [End User Guide](End%20User%20Guide.md)
**Complete guide for Loop users covering:**
- Quick setup and configuration
- How to use all search methods (text, barcode, voice, camera)
- Understanding results and nutrition information
- Advanced dosing recommendations (FPU, fiber analysis, exercise considerations)
- API cost estimates and usage management
- Best practices and troubleshooting basics

**Target Audience**: Loop users, diabetes patients, caregivers

### 🔧 [Configuration and Settings](Configuration%20and%20Settings.md)
**Detailed settings reference covering:**
- All available configuration options
- API provider setup (OpenAI, Claude, Gemini)
- Security and privacy settings
- Integration with existing Loop functionality
- Performance and accessibility options

**Target Audience**: End users, setup administrators

### 🛠️ [Technical Implementation Guide](Technical%20Implementation%20Guide.md)  
**Developer-focused implementation details:**
- Architecture overview and data flow
- Service layer implementation
- AI provider integration
- Advanced dosing system architecture
- Performance optimization strategies
- Security implementation
- Testing framework

**Target Audience**: Developers, contributors, technical reviewers

### 🚨 [Troubleshooting Guide](Troubleshooting%20Guide.md)
**Comprehensive problem-solving resource:**
- Common issues and solutions
- API connection troubleshooting
- Search and results problems
- Performance optimization
- Data privacy concerns
- Emergency guidance

**Target Audience**: All users, support staff

## Quick Start

### For End Users
1. Read the **[End User Guide](End%20User%20Guide.md)** for complete setup instructions
2. Follow the **Quick Setup** section to enable Food Search
3. Configure your preferred AI provider with API keys
4. Refer to **[Troubleshooting Guide](Troubleshooting%20Guide.md)** for any issues

### For Developers
1. Review **[Technical Implementation Guide](Technical%20Implementation%20Guide.md)** for architecture overview
2. Examine the codebase structure and key components
3. Review integration tests in `LoopTests/FoodSearchIntegrationTests.swift`
4. Follow development best practices outlined in the technical guide

## Key Features Covered

### Core Functionality
- ✅ Text-based food search with AI analysis
- ✅ Barcode scanner for packaged foods  
- ✅ Voice search with speech-to-text
- ✅ Camera analysis for food photos
- ✅ Favorite foods management
- ✅ Multi-provider AI integration

### Advanced Features
- ✅ **Advanced Dosing Recommendations** - Research-based diabetes guidance
- ✅ **Fat-Protein Units (FPU)** - Extended insulin dosing calculations
- ✅ **Fiber Impact Analysis** - Net carb adjustments
- ✅ **Exercise Considerations** - Activity-based recommendations  
- ✅ **Dynamic Absorption Timing** - Meal-specific timing guidance
- ✅ **Safety Alerts** - Important diabetes management warnings

### Integration Features
- ✅ Loop therapy settings integration
- ✅ Absorption time customization
- ✅ Nutrition circle visualization
- ✅ Progressive disclosure UI design
- ✅ Accessibility compliance

## API Provider Information

### Supported Providers

| Provider | Model | Cost Range | Strengths |
|----------|--------|------------|-----------|
| **OpenAI** | GPT-4o-mini | $0.001-0.003 | Most accurate analysis |
| **Claude** | Claude-3-haiku | $0.002-0.005 | Fast and reliable |
| **Gemini** | Gemini-1.5-flash | $0.0005-0.002 | Most cost-effective |

### Cost Estimates
- **Typical user**: $1.50-15/month (100-300 food analyses)
- **Heavy user**: $15-30/month (300+ analyses)
- **Cost optimization**: Use favorites, barcode scanner for packaged foods

## Safety and Privacy

### Data Privacy
- ✅ **Local Storage**: All analysis results stored on device only
- ✅ **No Personal Data**: No health information sent to AI providers
- ✅ **Anonymized Queries**: Food descriptions only, no user identifiers
- ✅ **Secure Communication**: TLS encryption for all API calls

### Medical Safety
- ⚠️ **Advisory Only**: All recommendations require healthcare provider review
- ⚠️ **User Judgment**: Always use clinical judgment for diabetes management
- ⚠️ **Emergency Backup**: Maintain traditional carb counting as backup method

## Version Information

**Current Version**: Loop Food Search v2.0+
**Compatibility**: iOS 14+, Loop v2.0+
**Last Updated**: July 2025

## Support Resources

### Community Support
- **Loop Facebook Groups**: User community discussions
- **Loop Forums**: Technical questions and feature discussions
- **GitHub Issues**: Bug reports and feature requests

### Professional Support  
- **Healthcare Providers**: Consult for diabetes management guidance
- **Diabetes Educators**: Integration with existing therapy plans
- **Technical Support**: For persistent technical issues

### Educational Resources
- **Diabetes Research**: Links to peer-reviewed studies used in advanced features
- **FPU Education**: Comprehensive Fat-Protein Unit learning resources
- **AI Technology**: Understanding AI analysis capabilities and limitations

## Contributing

### Documentation Updates
- Submit improvements via pull requests
- Follow existing documentation style
- Update version information when making changes
- Test all examples and procedures

### Feature Development
- Review **Technical Implementation Guide** before contributing
- Follow established architecture patterns
- Add comprehensive tests for new functionality  
- Update documentation for any new features

### Bug Reports
- Include specific error messages and steps to reproduce
- Specify device model, iOS version, and Loop version
- Attach relevant screenshots when helpful
- Check existing issues before submitting new reports

## Legal and Compliance

### Medical Device Considerations
- Food Search is a supportive tool, not a medical device
- Does not replace professional medical advice
- Users responsible for all diabetes management decisions
- Healthcare provider consultation recommended for therapy changes

### API Terms of Service
- Users responsible for compliance with AI provider terms
- API usage subject to provider rate limits and pricing
- Users must maintain valid API keys and billing information
- Respect provider usage policies and guidelines

### Open Source License
- Loop Food Search follows Loop's existing open source license
- Documentation available under Creative Commons license
- Contributions subject to project licensing terms

---

## Quick Links

- 📖 **[Complete End User Guide](End%20User%20Guide.md)** - Everything users need to know
- ⚙️ **[Settings Reference](Configuration%20and%20Settings.md)** - All configuration options  
- 💻 **[Technical Guide](Technical%20Implementation%20Guide.md)** - Implementation details
- 🔍 **[Troubleshooting](Troubleshooting%20Guide.md)** - Problem solving resource

*For the most up-to-date information, always refer to the latest documentation in this directory.*