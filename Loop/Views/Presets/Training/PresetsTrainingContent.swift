//
//  PresetsTrainingContent.swift
//  Loop
//
//  Created by Cameron Ingham on 8/26/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import LoopKitUI
import SwiftUI

extension PresetsTraining {
    enum CTA {
        case start
        case `continue`
        case close
        case closeOrContinue(_ to: String, chapter: Chapter)
    }
}

protocol PresetsTrainingContent {
    associatedtype B: View
    func content(appName: String, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, dynamicTypeSize: DynamicTypeSize, trainingContent: [MediaContent], next: @escaping () -> Void, onPlayMedia: @escaping (MediaContent) -> Void) -> B
    var cta: PresetsTraining.CTA? { get }
}

extension PresetsTraining.Step: PresetsTrainingContent {
    
    @ViewBuilder
    func content(appName: String, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, dynamicTypeSize: DynamicTypeSize, trainingContent: [MediaContent], next: @escaping () -> Void, onPlayMedia: @escaping (MediaContent) -> Void) -> some View {
        switch self {
        case .customizingPresets(let customizingPresets):
            switch customizingPresets {
            case .customizingPresets:
                if let image = Image.optional("PresetsTrainingCustomizingPresetsHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                EstimatedReadTime(.minutes(10))
                
                VStack(alignment: .leading) {
                    Text("This required training will show you how to change your settings with confidence and create custom presets that fit your needs.\n\nThis training covers:")
                        .fixedSize(horizontal: false, vertical: true)
                    
                    BulletedListView {
                        Text("How to configure each setting")
                        Text("How to use Presets when you are sick")
                        Text("How to use Presets for everyday activities")
                        ExerciseOptionalReader { isOptional in
                            isOptional ? Text("How to use Presets for exercise (optional)") : Text("How to use Presets for exercise")
                        }
                    }
                    .padding(.leading, 8)
                }

            case .overallInsulin:
                if let image = Image.optional("PresetsTrainingOverallInsulinHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                VStack(alignment: .leading) {
                    Text("The \"Overall Insulin\" percentage controls total insulin delivery by adjusting your:")
                        .fixedSize(horizontal: false, vertical: true)

                    BulletedListView {
                        Text("Basal Rate")
                        Text("Carb Ratio")
                        Text("Insulin Sensitivity Factor (ISF)")
                    }
                    .padding(.leading, 8)
                }
                
                Text("At 100%, \(appName) assumes your insulin needs are the same as usual.")
                
                Text("When deciding to adjust your overall insulin, **ask yourself, does my body need more or less than usual?**")
                
                Callout(.note) {
                    BulletedListView {
                        Text("A percentage **below 100%** tells the system you need **less** insulin")
                        
                        Text("A percentage **above 100%** tells the system you need **more** insulin")
                    }
                    .font(.footnote)
                    .padding(.top, 8)
                }
                .padding(.horizontal, -16)
                
            case .correctionRange:
                if let image = Image.optional("PresetsTrainingCorrectionRangeHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("Correction range is a **safety setting**. Changing it can help lower your risk of going low if you expect unusual changes.")
                
                Text("Changing it can lower the chance of your glucose levels going too low if you expect unusual changes.")
                
                Text("Choose the glucose value (or values) you want \(appName) to target when changing how much basal insulin you get.")
                
                Text("You don’t need to change the correction range for every preset. But before you decide to change it, ask yourself: *Am I more likely to go high or low during this time?*")
                
                Callout(.note) {
                    Text("To help avoid lows, set a range **higher** than your typical correction range.")
                        .font(.footnote)
                        .padding(.top, 8)
                }
                .padding(.horizontal, -16)
            }
        case .illness(let illness):
            switch illness {
            case .commonUses:
                Text("Complete each section below to learn how presets can be used for a variety of situations.")
                
                VStack(spacing: 16) {
                    CommonUseStep(
                        title: Text("Presets for Illness"),
                        readTime: .minutes(3),
                        onTapGesture: next
                    )
                    
                    CommonUseStep(
                        title: Text("Presets for Daily Activity"),
                        readTime: .minutes(2)
                    )
                    .disabled(true)
                    
                    ExerciseOptionalReader { isOptional in
                        CommonUseStep(
                            title: isOptional ? Text("Presets for Exercise (Optional)") : Text("Presets for Exercise"),
                            readTime: .minutes(5)
                        )
                    }
                    .disabled(true)
                }
                
            case .presetsForIllness:
                Text("Physical stress, like illness, can cause glucose to rise.")
                
                Text("Let’s walk through a simple example to show how a preset might be used in this situation.")
                
                InsetContent(alignment: .center, spacing: 10) {
                    Text("Example").fontWeight(.semibold).foregroundColor(.accentColor)
                    
                    Text("Paloma Porpoise sees her glucose is running higher than usual. She creates a preset to help manage her glucose while she is sick.").multilineTextAlignment(.center)
                }
                
                Text("Next, we’ll look at settings you can change and how they affect Paloma’s insulin.")
                
            case .overallInsulin:
                Text("Paloma wants \(appName) to know she needs more insulin than usual.")
                    .fixedSize(horizontal: false, vertical: true)

                TherapySettingsExampleView(
                    title: NSLocalizedString("Paloma’s Current Therapy Settings", comment: ""),
                    components: [
                        .basalRate(0.5),
                        .carbRatio(13),
                        .isf(50)
                    ]
                )
                
                Text("She can do this by raising her **Overall Insulin** setting. This tells \(appName) to deliver more than her usual amount, making her insulin settings stronger.")
                    .fixedSize(horizontal: false, vertical: true)

                if let image = Image.optional("PresetsTrainingIllnessOverallInsulin") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                TherapySettingsExampleView(
                    title: NSLocalizedString("Paloma’s Adjusted Therapy Settings", comment: ""),
                    components: [
                        .basalRate(0.6),
                        .carbRatio(12),
                        .isf(45)
                    ],
                    style: .adjusted
                )
                
            case .correctionRange:
                Text("While sick, Paloma expects to eat less or not absorb everything she eats.")
                
                TherapySettingsExampleView(
                    title: NSLocalizedString("Paloma’s Current Therapy Settings", comment: ""),
                    component: .correctionRange(105...110)
                )
                
                Text("To help prevent lows, she will increase her correction range.")
                
                if let image = Image.optional("PresetsTrainingIllnessCorrectionRange") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                TherapySettingsExampleView(
                    title: NSLocalizedString("Paloma’s Adjusted Therapy Settings", comment: ""),
                    component: .correctionRange(130...140),
                    style: .adjusted
                )
                
            case .duration:
                Text("You can choose how long your preset lasts.")
                
                Text("Since Paloma doesn't know when she'll feel better, she sets hers to “Until I Turn Off”.")
                
                if let image = Image.optional("PresetsTrainingIllnessDuration1") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("To be safe, \(appName) will remind her after 24 hours that the preset is still running.")
                
                if let image = Image.optional("PresetsTrainingIllnessDuration2") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("While turned on, Paloma’s preset will display on the home screen and in her Presets list.")
                
            case .impactOnBolusing:
                Text("Later that day, Paloma eats a meal with about 30g of carbs.")
                
                Text("How does her preset impact her bolus recommendation?")
                
                Text("Her preset is set to **110%**, which is more than she usually needs. This means \(appName) will make her basal rates, carb ratio, and insulin sensitivity factor (ISF) stronger. ")
                
                TherapySettingsExampleView(
                    title: NSLocalizedString("Her bolus recommendation is higher than usual because her overall insulin is set higher.", comment: ""),
                    component: .bolusRecommendation(
                        starting: 3.9,
                        ending: 4.3,
                        action: NSLocalizedString("With Preset On", comment: "")
                    ),
                    style: .adjusted
                )
            }
        case .dailyActivities(let dailyActivities):
            switch dailyActivities {
            case .commonUses:
                Text("You can use presets for a variety of situations. Explore the uses below to learn tips for these common scenarios.")
                
                VStack(spacing: 16) {
                    CommonUseStep(
                        title: Text("Presets for Illness"),
                        readTime: .minutes(3)
                    )
                    
                    CommonUseStep(
                        title: Text("Presets for Daily Activity"),
                        readTime: .minutes(2),
                        onTapGesture: next
                    )
                    
                    ExerciseOptionalReader { isOptional in
                        CommonUseStep(
                            title: isOptional ? Text("Presets for Exercise (Optional)") : Text("Presets for Exercise"),
                            readTime: .minutes(5)
                        )
                    }
                    .disabled(true)
                }
                
            case .presetsForDailyActivities:
                Text("For some people, routine chores and everyday activities can affect glucose levels similar to exercise.")
                
                Text("Let’s walk through a simple example to show how a preset might be used in this situation.")
                
                InsetContent(alignment: .center, spacing: 10) {
                    Text("Example").fontWeight(.semibold).foregroundColor(.accentColor)
                    
                    Text("Omar Octopus wants to create a preset for some yard work he’ll be doing around the house.").multilineTextAlignment(.center)
                }
                
                Text("Next, we’ll look at settings you can change and how they affect Omar’s insulin.")
                
                if let adls = trainingContent.first(where: { $0.fileName == "ADLs" }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Learn More")
                            .font(.headline.weight(.semibold))
                        
                        PlayMediaButton(mediaContent: adls, onPlay: onPlayMedia)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(colorPalette.chartColorPalette.presetTint).opacity(0.1))
                    )
                }
                
            case .overallInsulin:
                Text("Omar asks himself, **do I expect I will need more or less insulin than usual?**")
                
                Text("Since he doesn’t plan to push himself too hard, he expects his insulin needs to stay the same, so he leaves the setting at 100%.")
                
                if let image = Image.optional("PresetsTrainingDailyActivityOverallInsulin") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Callout(.note) {
                    Text("Pay attention to your insulin needs before and after exercising, playing sports, or doing unusually hard physical labor.")
                }
                .padding(.horizontal, -16)
                
            case .correctionRange:
                Text("For activities that raise your risk of going low, you can set a higher temporary correction range.")
                
                Text("This range is usually higher than your correction range when you are not exercising.")
                
                Text("Because Omar has gone low while working outdoors in the past, he raises his preset correction range to help prevent another low.")
                
                TherapySettingsExampleView(
                    title: NSLocalizedString("Omar’s Current Therapy Settings", comment: ""),
                    component: .correctionRange(110...120)
                )
                
                Text("Omar sets his correction range a little higher, to \(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 140), includeUnit: false))-\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 160), includeUnit: false)) \(displayGlucosePreference.unit.localizedShortUnitString). This tells \(appName) to step in sooner.")
                
                if let image = Image.optional("PresetsTrainingDailyActivityCorrectionRange") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
            case .savedPresets:
                if let image = Image.optional("PresetsTrainingDailyActivitySavedPresets") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("Once saved, Omar’s new preset will display in his Presets lists.")
                
                Callout(.note) {
                    Text("If your activity has a higher risk of low glucose, start a physical activity preset at least **1 hour before you begin** and keep it on until you finish.")
                    
                    Text("If you expect your glucose to rise during the activity, you may not need a preset.")
                }
                .padding(.horizontal, -16)
                
            }
        case .exercise(let exercise):
            switch exercise {
            case .commonUses:
                Text("Presets can be used for a variety of situations. Explore the uses below to learn tips for these common scenarios.")
                
                VStack(spacing: 16) {
                    CommonUseStep(
                        title: Text("Presets for Illness"),
                        readTime: .minutes(3)
                    )
                    
                    CommonUseStep(
                        title: Text("Presets for Daily Activity"),
                        readTime: .minutes(2)
                    )
                    
                    ExerciseOptionalReader { isOptional in
                        CommonUseStep(
                            title: isOptional ? Text("Presets for Exercise (Optional)") : Text("Presets for Exercise"),
                            readTime: .minutes(5),
                            onTapGesture: next
                        )
                    }
                }
            case .presetsForExercise:
                Text("Exercise is a common reason to use a preset. Different kinds of exercise and their intensity levels can affect your glucose levels in different ways.")
                
                Text("Depending on the activity, you may notice a few common patterns when it comes to your insulin needs:")
                
                BulletedListView {
                    Text("no change needed")
                    Text("you need **less** insulin than usual")
                    Text("you need **more** insulin than usual")
                }
                
                Text("Let’s walk through some examples to show how presets might be used in these situations.")
                
                Callout(.note) {
                    Text("These patterns are based on published exercise consensus guidelines and are meant to be used as a starting point. What works for one person may not work for you.")
                }
                .padding(.horizontal, -16)
                
            case .perceivedIntensity:
                Text("Recognizing how hard you feel you're working during exercise can help you understand its impact on your glucose levels.")
                
                Text("Consider an exercise you do regularly and think about how hard you push yourself.")
                
                Text("Use the slider to rate the effort on a scale of 0–10, with 10 being the hardest you’ve ever worked.")
                
                IntensityInfo()
                
                if let sameActivityDifferentIntensity = trainingContent.first(where: { $0.fileName == "Same Activity Different Intensity" }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Learn More")
                            .font(.headline.weight(.semibold))
                        
                        PlayMediaButton(mediaContent: sameActivityDifferentIntensity, onPlay: onPlayMedia)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(colorPalette.chartColorPalette.presetTint).opacity(0.1))
                    )
                }
                
            case .lightToModerateExercise:
                if let image = Image.optional("PresetsTrainingExerciseLightToModerateHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("Light-to-moderate intensity exercise can cause a drop in glucose levels. This is because your body uses glucose (or sugar) for energy during physical activity.")
                
                InsetContent {
                    VStack(spacing: 4) {
                        Text("Aerobic")
                            .font(.title2.bold())
                        
                        Text("Continuous or exercise without breaks")
                            .frame(maxWidth: .infinity)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Bullet(color: .secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Walking")

                                ActivityPresetTip(Text(" **Tip** Use your \(Image(systemName: "figure.walk")) **Walking** preset"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Bullet(color: .secondary)
                            
                            Text("Hiking")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Bullet(color: .secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Jogging")

                                ActivityPresetTip(Text(" **Tip** Use your \(Image(systemName: "figure.run")) **Jogging** preset"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Bullet(color: .secondary)
                            
                            Text("Swimming")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Text("For these activities, consider setting your insulin needs to **less than 100%**.")
                
                if let image = Image.optional("PresetsTrainingExerciseLightToModerate") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Callout(.note) {
                    Text("These recommendations should be used as a starting point. Checking your glucose during exercise will help you find the settings that work best for you.")
                }
                .padding(.horizontal, -16)
                
            case .highIntensityExercise:
                if let image = Image.optional("PresetsTrainingExerciseHighHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("High-intensity exercise means pushing yourself to your **maximum effort**. It is so hard that talking is nearly impossible, and you can’t keep it up for very long.")
                
                Text("During this kind of hard exercise, your body may release hormones that raise glucose. This is more common in the morning before eating.")
                
                InsetContent {
                    VStack(spacing: 4) {
                        Text("Anaerobic")
                            .font(.title2.bold())
                        
                        Text("Explosive sprints or bursts")
                            .frame(maxWidth: .infinity)
                    }
                    
                    BulletedListView(bulletColor: .secondary) {
                        Text("Power lifting")
                        Text("CrossFit")
                        Text("100m sprint")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text("For these activities, consider setting your insulin needs to **more than 100%**.")
                
                Text("That said, insulin needs vary from person to person. Some people find they don’t need to adjust their insulin at all for high-intensity exercise.")
                
                Text("If you haven’t noticed a rise in glucose with high-intensity exercise, it may be due to:")
                
                BulletedListView {
                    Text("Starting your exercise with high active insulin")
                    Text("Automated insulin adjustments by \(appName) reduce a noticeable rise in glucose")
                    Text("The exercise may not be vigorous enough to produce these results")
                }
                
                if let image = Image.optional("PresetsTrainingExerciseHigh") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("When using high-insulin presets, **you may not need to start your preset 1 hour before**.")
                
                Callout(.note) {
                    Text("These recommendations should be used as a starting point. Checking your glucose during exercise will help you find the settings that work best for you.")
                }
                .padding(.horizontal, -16)
                
            case .mixedIntensityExercise:
                if let image = Image.optional("PresetsTrainingExerciseMixedHero") {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                
                Text("Mixed-intensity exercise may cause only small changes in glucose levels. Your glucose may go up or down.")
                
                InsetContent {
                    VStack(spacing: 4) {
                        Text("Aerobic and Anaerobic")
                            .font(.title2.bold())
                        
                        Text("Combination of high and low intensity")
                            .frame(maxWidth: .infinity)
                    }
                    
                    BulletedListView(bulletColor: .secondary) {
                        Text("Soccer")
                        Text("Interval Training ")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text("For mixed-intensity activity:")
                
                BulletedListView {
                    Text("If your glucose goes up, you may only need a small increase in insulin — less than you would for high-intensity activity.")
                    
                    Text("If your glucose goes down, you may only need a small decrease in insulin — less than you would for low to moderate-intensity activity.")
                }
                
                Callout(.note) {
                    Text("These recommendations should be used as a starting point. Checking your glucose during exercise will help you find the settings that work best for you.")
                }
                .padding(.horizontal, -16)
                
                if let mixedExercise = trainingContent.first(where: { $0.fileName == "Mixed Exercise" }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Learn More")
                            .font(.headline.weight(.semibold))
                        
                        PlayMediaButton(mediaContent: mixedExercise, onPlay: onPlayMedia)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(colorPalette.chartColorPalette.presetTint).opacity(0.1))
                    )
                }
                
            case .exerciseAndGlucoseActiveInsulin:
                Text("When using a preset for activity, keep in mind four key factors that may impact your  glucose.")
                
                TintedContent(
                    tint: colorPalette.insulinTintColor,
                    icon: Image(systemName: "cross.vial"),
                    title: Text("Active Insulin")
                ) {
                    Text("If you have active insulin in your body when you start exercising, you generally have an increased risk of low glucose.")
                    
                    TintedTip(text: Text("**Tip:** Try exercising when your active insulin is close to zero at the start of an activity."))
                }
                
            case .exerciseAndGlucoseTimeOfDay:
                Text("When using a preset for activity, keep in mind four key factors that may impact your  glucose.")
                
                TintedContent(
                    tint: colorPalette.carbTintColor,
                    icon: Image(systemName: "clock"),
                    title: Text("Time of Day")
                ) {
                    Text("Morning exercise before eating (like a fasted jog) usually causes a smaller drop in glucose levels and may even promote a rise, compared to afternoon exercise.")
                    
                    if dynamicTypeSize < .accessibility1 {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Morning Exercise")
                                    .foregroundStyle(colorPalette.carbTintColor)
                                    .font(.subheadline.weight(.semibold))
                                
                                Text("Smaller glucose drop")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Afternoon Exercise")
                                    .foregroundStyle(colorPalette.guidanceColors.critical)
                                    .font(.subheadline.weight(.semibold))
                                
                                Text("Larger glucose drop")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                        }
                    } else {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Morning Exercise")
                                    .foregroundStyle(colorPalette.carbTintColor)
                                    .font(.subheadline.weight(.semibold))
                                
                                Text("Smaller glucose drop")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Afternoon Exercise")
                                    .foregroundStyle(colorPalette.guidanceColors.critical)
                                    .font(.subheadline.weight(.semibold))
                                
                                Text("Larger glucose drop")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                        }
                    }
                    
                    TintedTip(text: Text("**Try:** If you often experience low glucose, consider exercising earlier in the day before eating."))
                }
                
            case .exerciseAndGlucoseMealTiming:
                Text("When using a preset for activity, keep in mind four key factors that may impact your  glucose.")
                
                TintedContent(
                    tint: .orange,
                    icon: Image(systemName: "fork.knife"),
                    title: Text("Meal Timing")
                ) {
                    Text("If you often experience low glucose, you may need to reduce how much insulin you deliver for meals eaten 1-2 hours before exercising.")
                    
                    VStack(spacing: 4) {
                        Text("Recommended Insulin Reduction")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        
                        Text("25-33%")
                            .font(.title.weight(.heavy))
                            .foregroundStyle(Color.orange)
                        
                        Text("if eating less than 2 hours before exercise")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                    
                    TintedTip(text: Text("**Try:** Reducing your meal bolus if you expect your glucose to drop."))
                }
                
            case .exerciseAndGlucoseCompetitionStress:
                Text("When using a preset for activity, keep in mind four key factors that may impact your  glucose.")
                
                TintedContent(
                    tint: colorPalette.glucoseTintColor,
                    icon: Image(systemName: "trophy"),
                    title: Text("Competition Stress")
                ) {
                    Text("Stress during a game, match or tournament causes your body to release hormones like adrenaline and cortisol, which may raise your glucose and cause \(appName) to increase insulin delivery.")
                    
                    BulletedListView(bulletColor: colorPalette.glucoseTintColor, bulletOpacity: 1) {
                        Text("Monitor your glucose and active insulin at the start of a competition day")
                        
                        Text("Stay hydrated")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground)))
                    
                    TintedTip(text: Text("**Tip: If glucose rises to >270 mg/dl,** check \(appName) to see if a bolus is recommended to bring your glucose back into range."))
                }
                
            case .preventingLows:
                Text("If you usually experience lows while exercising, watch your glucose levels closely during exercise and consider eating around 3 to 20g of fast-acting carbs.")
                
                Group {
                    if dynamicTypeSize < .accessibility1 {
                        HStack(alignment: .bottom, spacing: 12) {
                            InsetContent(spacing: 8) {
                                Text("Stable Glucose")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                Image("glucose-stable")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(colorPalette.glucoseTintColor)
                                
                                VStack(spacing: 0) {
                                    Text("3-6")
                                        .font(.headline.weight(.semibold))
                                    
                                    Text("grams")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            InsetContent(spacing: 8) {
                                Text("Falling Slowly")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                Image("glucose-stable")
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(30))
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(colorPalette.glucoseTintColor)
                                
                                VStack(spacing: 0) {
                                    Text("6-9")
                                        .font(.headline.weight(.semibold))
                                    
                                    Text("grams")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            InsetContent(spacing: 8) {
                                Text("Falling / Falling Quickly")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                HStack(spacing: 6) {
                                    Image("glucose-stable")
                                        .resizable()
                                        .scaledToFit()
                                        .rotationEffect(.degrees(90))
                                        .frame(width: 28, height: 28)
                                    
                                    Image("glucose-falling-fast")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                }
                                .foregroundStyle(colorPalette.glucoseTintColor)
                                
                                VStack(spacing: 0) {
                                    Text("9-20")
                                        .font(.headline.weight(.semibold))
                                    
                                    Text("grams")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 12) {
                            InsetContent(spacing: 8) {
                                Text("Stable Glucose")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                Image("glucose-stable")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(colorPalette.glucoseTintColor)

                                Text("3-6")
                                    .font(.headline.weight(.semibold))
                                + Text(" grams")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            InsetContent(spacing: 8) {
                                Text("Falling Slowly")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                Image("glucose-stable")
                                    .resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(30))
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(colorPalette.glucoseTintColor)
                                
                                Text("6-9")
                                    .font(.headline.weight(.semibold))
                                + Text(" grams")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            
                            InsetContent(spacing: 8) {
                                Text("Falling / Falling Quickly")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxHeight: .infinity)
                                
                                HStack(spacing: 6) {
                                    Image("glucose-stable")
                                        .resizable()
                                        .scaledToFit()
                                        .rotationEffect(.degrees(90))
                                        .frame(width: 28, height: 28)
                                    
                                    Image("glucose-falling-fast")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                }
                                .foregroundStyle(colorPalette.glucoseTintColor)
                                
                                Text("9-20")
                                    .font(.headline.weight(.semibold))
                                + Text(" grams")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.center)
                
                Text("Check your glucose levels around 20 to 30 min after eating. If you're still low, consider eating the same amount.")
                
                Callout(.note) {
                    Text("If your glucose isn't dropping, eating too many carbs can raise your blood sugar, trigger more insulin, and increase the risk of low blood sugar during or after the activity.")
                }
                .padding(.horizontal, -16)
                
            case .unplannedActivity:
                Text("Planning for physical activity can be tough. If you forget to set a preset ahead of time, consider these strategies:")
                
                InsetContent(padding: 16) {
                    HStack(spacing: 16) {
                        Image("presets-selected")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Color(colorPalette.chartColorPalette.presetTint))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Preset")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fontWeight(.semibold)
                            
                            Text("Turn on the preset as soon as you remember and keep it on until the activity ends")
                        }
                    }
                }
                
                InsetContent(padding: 16) {
                    HStack(spacing: 16) {
                        Image("candy-icon")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(colorPalette.carbTintColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("If glucose drops below 126 mg/dL")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fontWeight(.semibold)
                            
                            Text("Consider eating around 10 to 20 grams of fast-acting carbs")
                        }
                    }
                }
            }
        case .trainingComplete:
            Text("Congratulations! You've finished the Presets training.")
            
            VStack(alignment: .leading, spacing: 8) {
                Text("You can now:")
                
                BulletedListView {
                    Text("Edit presets")
                    Text("Create new presets")
                }
                .padding(.leading, 8)
            }
            
            Text("You may review the training materials again at any time via the Learning Hub, located at the bottom of the Preset screen.")

            ExerciseOptionalReader { isOptional, isExerciseComplete in
                if isOptional && !isExerciseComplete {
                    Text("Presets for Exercise is optional. The Learning Hub opens it whenever you want to read it.")
                }
            }
        }
    }
    
    var references: [Text] {
        switch self {
        case .customizingPresets, .illness, .dailyActivities, .trainingComplete:
            return []
        case .exercise(let exercise):
            switch exercise {
            case .commonUses:
                return []
            case .presetsForExercise:
                return [
                    Text(verbatim: "Moser O, Zaharieva DP, Adolfsson A, Battelino T, Bracken RM, Buckingham BA, Danne T, Davis EA, Dovč K, Forlenza GP, et al. The use of automated insulin delivery around physical activity and exercise in type 1 diabetes: a position statement of the European Association for the Study of Diabetes (EASD) and the International Society for Pediatric and Adolescent Diabetes (ISPAD). ") + Text(verbatim: "[PMID: 39653802](https://pmc.ncbi.nlm.nih.gov/articles/PMC11732933/)").underline(),
                    Text(verbatim: "American Diabetes Association Professional Practice Committee. 14. Children and Adolescents: Standards of Care in Diabetes-2025. Diabetes Care. ") + Text(verbatim: "[PMID: 39651980](https://doi.org/10.2337/dc25-S014)").underline(),
                    Text(verbatim: "Adolfsson P, Taplin CE, Zaharieva DP, Pemberton J, Davis EA, Riddell MC, et al. ISPAD Clinical Practice Consensus Guidelines 2022: Exercise in children and adolescents with diabetes. ") + Text(verbatim: "[PMID: 36537529](https://doi.org/10.1111/pedi.13452)").underline(),
                    Text(verbatim: "Phillip M, Nimri R, Bergenstal RM, Barnard-Kelly K, Danne T, Hovorka R, et al. Consensus Recommendations for the Use of Automated Insulin Delivery Technologies in Clinical Practice. ") + Text(verbatim: "[PMID: 36066457](https://pmc.ncbi.nlm.nih.gov/articles/PMC9985411/)").underline(),
                    Text(verbatim: "Braune K, Lal RA, Petruželková L, Scheiner G, Winterdijk P, Schmidt S, et al. Open-source automated insulin delivery: international consensus statement and practical guidance for health-care professionals. ") + Text(verbatim: "[PMID: 34785000](https://www.thelancet.com/journals/landia/article/PIIS2213-8587(21)00267-9/abstract)").underline(),
                    Text(verbatim: "Moser O, Riddell MC, Eckstein ML, Adolfsson P, Rabasa-Lhoret R, van den Boom L, et al. Glucose management for exercise using continuous glucose monitoring (CGM) and intermittently scanned CGM (isCGM) systems in type 1 diabetes: position statement of the European Association for the Study of Diabetes (EASD) and of the International Society for Pediatric and Adolescent Diabetes (ISPAD) endorsed by JDRF and supported by the American Diabetes Association (ADA). ") + Text(verbatim: "[PMID: 33047169](https://link.springer.com/article/10.1007/s00125-020-05263-9)").underline(),
                    Text(verbatim: "Scott SN, Fontana FY, Cocks M, Morton JP, Jeukendrup A, Dragulin R, et al. Post-exercise recovery for the endurance athlete with type 1. ") + Text(verbatim: "[PMID: 33864810](https://pubmed.ncbi.nlm.nih.gov/33864810/)").underline(),
                    Text(verbatim: "Riddell MC, Gallen IW, Smart CE, Taplin CE, Adolfsson P, Lumb AN, et al. Exercise management in type 1 diabetes: a consensus statement. ") + Text(verbatim: "[PMID: 28126459](https://pubmed.ncbi.nlm.nih.gov/28126459/)").underline(),
                    Text(verbatim: "Yardley JE, Sigal RJ. Exercise strategies for hypoglycemia prevention in individuals with type 1 diabetes. ") + Text(verbatim: "[PMID: 25717276](https://pmc.ncbi.nlm.nih.gov/articles/PMC4334090/)").underline(),
                    Text(verbatim: "Colberg SR, Sigal RJ, Yardley JE, Riddell MC, Dunstan DW, Dempsey PC, et al. Physical Activity/Exercise and Diabetes: A Position Statement of the American Diabetes Association. ") + Text(verbatim: "[PMID: 27926890](https://pmc.ncbi.nlm.nih.gov/articles/PMC6908414/)").underline()
                ]
            case .perceivedIntensity:
                return [
                    Text(verbatim: "Zaharieva DP, Paldus B, Morrison D, Messer LH, O’Neal DN, Maahs DM, Riddell MC, et al. Practical aspects and exercise safety benefits of automated insulin delivery systems in type 1 diabetes. Diabetes Spectr. ") + Text(verbatim: "[PMID: 37193203](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182962/)").underline(),
                    Text(verbatim: "Borg GA. Psychophysical bases of perceived exertion. Med Sci Sports Exerc. PMID: ") + Text(verbatim: "[PMID: 7154893](https://pubmed.ncbi.nlm.nih.gov/7154893/)").underline()
                ]
            case .lightToModerateExercise:
                return [
                    Text(verbatim: "Turner LV, Marak MC, Gal RL, Calhoun P, Li Z, Jacobs PG, Clements MA, Martin CK, Doyle FJ 3rd, Patton SR, Castle JR, Gillingham MB, Beck RW, Rickels MR, Riddell MC; T1DEXI Study Group. Associations between daily step count classifications and continuous glucose monitoring metrics in adults with type 1 diabetes: analysis of the Type 1 Diabetes Exercise Initiative (T1DEXI) cohort. ") + Text(verbatim: "[PMID: 38502241](https://pubmed.ncbi.nlm.nih.gov/38502241/)").underline(),
                    Text(verbatim: "Riddell MC, Gal RL, Bergford S, Patton SR, Clements MA, Calhoun P, Beaulieu LC, Sherr JL. The Acute Effects of Real-World Physical Activity on Glycemia in Adolescents With Type 1 Diabetes: The Type 1 Diabetes Exercise Initiative Pediatric (T1DEXIP) Study. ") + Text(verbatim: "[PMID: 37922335](https://pubmed.ncbi.nlm.nih.gov/37922335/)").underline(),
                    Text(verbatim: "Zaharieva DP, McGaugh S, Pooni R, Vienneau T, Ly T, Riddell MC. Improved Open-Loop Glucose Control With Basal Insulin Reduction 90 Minutes Before Aerobic Exercise in Patients With Type 1 Diabetes on Continuous Subcutaneous Insulin Infusion. ") + Text(verbatim: "[PMID: 30796112](https://pubmed.ncbi.nlm.nih.gov/30796112/)").underline(),
                    Text(verbatim: "Molveau J, Myette-Côté É, Guédet C, Tagougui S, St-Amand R, Suppère C, Heyman E, Messier V, Boudreau V, Legault L, Rabasa-Lhoret R. Impact of pre- and post-exercise strategies on hypoglycemic risk for two modalities of aerobic exercise among adults and adolescents living with type 1 diabetes using continuous subcutaneous insulin infusion: A randomized controlled trial. ") + Text(verbatim: "[PMID: 39653075](https://pubmed.ncbi.nlm.nih.gov/39653075/)").underline(),
                    Text(verbatim: "Tagougui S, Legault L, Heyman E, Messier V, Suppere C, Potter KJ, Pigny P, Berthoin S, Taleb N, Rabasa-Lhoret R. Anticipated Basal Insulin Reduction to Prevent Exercise-Induced Hypoglycemia in Adults and Adolescents Living with Type 1 Diabetes. ") + Text(verbatim: "[PMID: 35099281](https://pubmed.ncbi.nlm.nih.gov/35099281/)").underline()
                ]
            case .highIntensityExercise:
                return [
                    Text(verbatim: "Paldus B, Morrison D, Zaharieva DP, Lee MH, Jones H, Obeyesekere V, La Gerche A, et al. A randomized crossover trial comparing glucose control during moderate‑intensity, high‑intensity, and resistance exercise with hybrid closed‑loop insulin delivery while profiling potential additional signals in adults with type 1 diabetes. Diabetes Care. ") + Text(verbatim: "[PMID: 34789504](https://pubmed.ncbi.nlm.nih.gov/34789504/)").underline(),
                    Text(verbatim: "Aronson R, Brown RE, Li A, Riddell MC. Optimal insulin correction factor in post‑high‑intensity exercise hyperglycemia in adults with type 1 diabetes: The FIT Study. Diabetes Care. ") + Text(verbatim: "[PMID: 30455336](https://pubmed.ncbi.nlm.nih.gov/30455336/)").underline()
                ]
            case .mixedIntensityExercise:
                return [
                    Text(verbatim: "Riddell MC, Gal RL, Bergford S, Patton SR, Clements MA, Calhoun P, et al. The Acute Effects of Real‑World Physical Activity on Glycemia in Adolescents With Type 1 Diabetes: The Type 1 Diabetes Exercise Initiative Pediatric (T1DEXIP) Study. ") + Text(verbatim: "[PMID: 37922335](https://pubmed.ncbi.nlm.nih.gov/37922335/)").underline(),
                    Text(verbatim: "Zaharieva DP, Yavelberg L, Jamnik V, Cinar A, Turksoy K, Riddell MC. The Effects of Basal Insulin Suspension at the Start of Exercise on Blood Glucose Levels During Continuous Versus Circuit‑Based Exercise in Individuals with Type 1 Diabetes on Continuous Subcutaneous Insulin Infusion. ") + Text(verbatim: "[PMID: 28613947](https://pmc.ncbi.nlm.nih.gov/articles/PMC5510047/)").underline()
                ]
            case .exerciseAndGlucoseActiveInsulin:
                return [
                    Text(verbatim: "Riddell MC, Lewis DM, Turner LV, Lal RA, Shahid A, Zaharieva DP. Refining Insulin on Board with netIOB for Automated Insulin Delivery. ") + Text(verbatim: "[PMID: 39143692](https://pmc.ncbi.nlm.nih.gov/articles/PMC11571556/)").underline(),
                    Text(verbatim: "Li Z, Calhoun P, Rickels MR, Gal RL, Beck RW, Jacobs PG, et al. Factors Affecting Reproducibility of Change in Glucose During Exercise: Results From the Type 1 Diabetes and Exercise Initiative. ") + Text(verbatim: "[PMID: 38456512](https://pmc.ncbi.nlm.nih.gov/articles/PMC11571421/)").underline(),
                    Text(verbatim: "Zaharieva DP, Morrison D, Paldus B, Lal RA, Buckingham BA, O'Neal DN. Practical Aspects and Exercise Safety Benefits of Automated Insulin Delivery Systems in Type 1 Diabetes. ") + Text(verbatim: "[PMID: 37193203](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182962/)").underline()
                ]
            case .exerciseAndGlucoseTimeOfDay:
                return [
                    Text(verbatim: "Riddell MC, Turner LV, Patton SR. Is There an Optimal Time of Day for Exercise? A Commentary on When to Exercise for People Living With Type 1 or Type 2 Diabetes. ") + Text(verbatim: "[PMID: 37193212](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182965/)").underline(),
                    Text(verbatim: "Morrison D, Paldus B, Zaharieva DP, Lee MH, Vogrin S, Jenkins AJ, et al. Late Afternoon Vigorous Exercise Increases Postmeal but Not Overnight Hypoglycemia in Adults with Type 1 Diabetes Managed with Automated Insulin Delivery. ") + Text(verbatim: "[PMID: 36094458](https://pubmed.ncbi.nlm.nih.gov/36094458/)").underline(),
                    Text(verbatim: "Yardley JE. Fasting May Alter Blood Glucose Responses to High-Intensity Interval Exercise in Adults With Type 1 Diabetes: A Randomized, Acute Crossover Study. ") + Text(verbatim: "[PMID: 33160882](https://pubmed.ncbi.nlm.nih.gov/33160882/)").underline(),
                    Text(verbatim: "Toghi-Eshghi SR, Yardley JE. Morning (Fasting) vs Afternoon Resistance Exercise in Individuals With Type 1 Diabetes: A Randomized Crossover Study. ") + Text(verbatim: "[PMID: 31211392](https://academic.oup.com/jcem/article/104/11/5217/5519298)").underline()
                ]
            case .exerciseAndGlucoseMealTiming:
                return [
                    Text(verbatim: "McCarthy OM, Christensen MB, Kristensen KB, Schmidt S, Ranjan AG, Bain SC, Bracken RM, Nørgaard K. Automated Insulin Delivery Around Exercise in Adults with Type 1 Diabetes: A Pilot Randomized Controlled Study. ") + Text(verbatim: "[PMID: 37053529](https://pubmed.ncbi.nlm.nih.gov/37053529/)").underline(),
                    Text(verbatim: "Myette‑Côté É, Molveau J, Wu Z, Raffray M, Devaux M, Tagougui S, et al. A Randomized Crossover Pilot Study Evaluating Glucose Control During Exercise Initiated 1 or 2 h After a Meal in Adults with Type 1 Diabetes Treated with an Automated Insulin Delivery System. ") + Text(verbatim: "[PMID: 36399114](https://pmc.ncbi.nlm.nih.gov/articles/PMC9894601/)").underline(),
                    Text(verbatim: "Tagougui S, Taleb N, Legault L, Suppère C, Messier V, Boukabous I, Shohoudi A, Ladouceur M, Rabasa-Lhoret R. A single-blind, randomised, crossover study to reduce hypoglycaemia risk during postprandial exercise with closed-loop insulin delivery in adults with type 1 diabetes: announced (with or without bolus reduction) vs unannounced exercise strategies. ") + Text(verbatim: "[PMID: 32740723](https://link.springer.com/article/10.1007/s00125-020-05244-y)").underline()
                ]
            case .exerciseAndGlucoseCompetitionStress:
                return [
                    Text(verbatim: "Katz A, Shulkin A, Fortier MA, Yardley JE, Kichler J, Housni A, Talbo MK, Rabasa-Lhoret R, Brazeau AS. Strategies to reduce hyperglycemia-related anxiety in elite athletes with type 1 diabetes: A qualitative analysis. ") + Text(verbatim: "[PMID: 39823464](https://pubmed.ncbi.nlm.nih.gov/39823464/)").underline(),
                    Text(verbatim: "Riddell MC, Gallen IW, Smart CE, Taplin CE, Adolfsson P, Lumb AN, Kowalski A, Rabasa-Lhoret R, McCrimmon RJ, Hume C, Annan F, Fournier PA, Graham C, Bode B, Galassetti P, Jones TW, Millán IS, Heise T, Peters AL, Petz A, Laffel LM. Exercise management in type 1 diabetes: a consensus statement. ") + Text(verbatim: "[PMID: 28126459](https://pubmed.ncbi.nlm.nih.gov/28126459/)").underline(),
                    Text(verbatim: "Hobbs N, Brandt R, Maghsoudipour S, Sevil M, Rashid M, Quinn L, Cinar A. Observational Study of Glycemic Impact of Anticipatory and Early-Race Athletic Competition Stress in Type 1 Diabetes. ") + Text(verbatim: "[PMID: 36992757](https://pubmed.ncbi.nlm.nih.gov/36992757/)").underline(),
                    Text(verbatim: "Riddell MC, Scott SN, Fournier PA, Colberg SR, Gallen IW, Moser O, Stettler C, Yardley JE, Zaharieva DP, Adolfsson P, Bracken RM. The competitive athlete with type 1 diabetes. ") + Text(verbatim: "[PMID: 32533229](https://pubmed.ncbi.nlm.nih.gov/32533229/)").underline()
                ]
            case .preventingLows:
                return [
                    Text(verbatim: "Moser O, Zaharieva DP, Adolfsson P, Battelino T, Bracken RM, Buckingham BA, et al. The use of automated insulin delivery around physical activity and exercise in type 1 diabetes: a position statement of the European Association for the Study of Diabetes (EASD) and the International Society for Pediatric and Adolescent Diabetes (ISPAD). ") + Text(verbatim: "[PMID: 39653802](https://pubmed.ncbi.nlm.nih.gov/39653802/)").underline()
                ]
            case .unplannedActivity:
                return [
                    Text(verbatim: "Tagougui S, Taleb N, Legault L, Suppère C, Messier V, Boukabous I, Shohoudi A, Ladouceur M, Rabasa-Lhoret R. A single-blind, randomised, crossover study to reduce hypoglycaemia risk during postprandial exercise with closed-loop insulin delivery in adults with type 1 diabetes: announced (with or without bolus reduction) vs unannounced exercise strategies. ") + Text(verbatim: "[PMID: 32740723](https://pubmed.ncbi.nlm.nih.gov/32740723/)").underline(),
                    Text(verbatim: "Zimmer RT, Auth A, Schierbauer J, Haupt S, Wachsmuth N, Zimmermann P, Voit T, Battelino T, Sourij H, Moser O. (Hybrid) Closed-Loop Systems: From Announced to Unannounced Exercise. ") + Text(verbatim: "[PMID: 38133645](https://pubmed.ncbi.nlm.nih.gov/38133645/)").underline(),
                    Text(verbatim: "Dovc K, Piona C, Yeşiltepe Mutlu G, Bratina N, Jenko Bizjan B, Lepej D, Nimri R, Atlas E, Muller I, Kordonouri O, Biester T, Danne T, Phillip M, Battelino T. Faster Compared With Standard Insulin Aspart During Day-and-Night Fully Closed-Loop Insulin Therapy in Type 1 Diabetes: A Double-Blind Randomized Crossover Trial. ") + Text(verbatim: "[PMID: 31575640](https://pubmed.ncbi.nlm.nih.gov/31575640/)").underline(),
                    Text(verbatim: "Dovc K, Macedoni M, Bratina N, Lepej D, Nimri R, Atlas E, Muller I, Kordonouri O, Biester T, Danne T, Phillip M, Battelino T. Closed-loop glucose control in young people with type 1 diabetes during and after unannounced physical activity: a randomised controlled crossover trial. ") + Text(verbatim: "[PMID: 28840263](https://pubmed.ncbi.nlm.nih.gov/28840263/)").underline()
                ]
            }
        }
    }
    
    var cta: PresetsTraining.CTA? {
        switch self {
        case .customizingPresets: .continue
        case .illness(let illness):
            switch illness {
            case .commonUses: nil
            case .presetsForIllness,
                 .overallInsulin,
                 .correctionRange,
                 .duration,
                 .impactOnBolusing: .continue
            }
        case .dailyActivities(let dailyActivities):
            switch dailyActivities {
            case .commonUses: nil
            case .presetsForDailyActivities,
                 .overallInsulin,
                 .correctionRange,
                 .savedPresets: .continue
            }
        case .exercise(let exercise):
            switch exercise {
            case .commonUses: nil
            case .presetsForExercise,
                 .perceivedIntensity,
                 .lightToModerateExercise,
                 .highIntensityExercise,
                 .mixedIntensityExercise,
                 .exerciseAndGlucoseActiveInsulin,
                 .exerciseAndGlucoseTimeOfDay,
                 .exerciseAndGlucoseMealTiming,
                 .exerciseAndGlucoseCompetitionStress,
                 .preventingLows,
                 .unplannedActivity: .continue
            }
        case .trainingComplete: .close
        }
    }
}

extension PresetsTraining.Chapter: PresetsTrainingContent {
    @ViewBuilder
    func content(
        appName: String,
        displayGlucosePreference: DisplayGlucosePreference,
        colorPalette: LoopUIColorPalette,
        dynamicTypeSize: DynamicTypeSize,
        trainingContent: [MediaContent],
        next: @escaping () -> Void,
        onPlayMedia: @escaping (MediaContent) -> Void
    ) -> some View {
        firstStep.content(
            appName: appName,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: colorPalette,
            dynamicTypeSize: dynamicTypeSize,
            trainingContent: trainingContent,
            next: next,
            onPlayMedia: onPlayMedia
        )
    }
    
    var cta: PresetsTraining.CTA? {
        firstStep.cta
    }
}

private struct ExerciseOptionalReader<Content: View>: View {
    @Environment(PresetsTraining.self) private var training

    private let content: (_ isOptional: Bool, _ isExerciseComplete: Bool) -> Content

    init(@ViewBuilder content: @escaping (_ isOptional: Bool, _ isExerciseComplete: Bool) -> Content) {
        self.content = content
    }

    init(@ViewBuilder content: @escaping (_ isOptional: Bool) -> Content) {
        self.content = { isOptional, _ in content(isOptional) }
    }

    var body: some View {
        content(
            !training.trainingCompletion.isRequired(.exercise),
            training.trainingCompletion.completedChapters[.exercise] == true
        )
    }
}

/// Points at a built-in activity preset, so it is left out while those are hidden.
private struct ActivityPresetTip: View {
    @Environment(PresetsTraining.self) private var training

    private let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        if training.trainingCompletion.exerciseRequired {
            HStack(alignment: .center, spacing: 2) {
                Text("\(Image(systemName: "lightbulb.max"))")

                text
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color(UIColor.secondarySystemBackground).cornerRadius(5))
        }
    }
}
