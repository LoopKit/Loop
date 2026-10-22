# Acknowledgements

Third-party material bundled with Loop, and the terms it is used under.

## Alarm and alert sounds

The themed glucose alarm sets (Acoustic, Electronic) and the one-off tones in
`Loop/Resources/Sounds` were created by a sound designer for the Trio project
and contributed to Loop for distribution as part of the app.

## Voice alerts

The spoken alert sounds were generated with
[Piper](https://github.com/rhasspy/piper) using voices from the
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) collection.

### Amy (`voice_*_amy.caf`)

- Model: `en/en_US/amy/medium`
- Source dataset: [MycroftAI/mimic3-voices](https://github.com/MycroftAI/mimic3-voices)
- Licence: **Creative Commons Attribution-ShareAlike 4.0 International
  (CC BY-SA 4.0)** — <https://creativecommons.org/licenses/by-sa/4.0/>
- Changes made: the generated phrases were looped to a minimum duration of
  five seconds so a spoken alert lasts long enough to be heard as an alarm,
  then encoded to IMA4 `.caf`. No other processing was applied.
- These audio files are made available under CC BY-SA 4.0. This does not
  change the licence of Loop itself.

### Bryce (`voice_*_bryce.caf`)

- Model: `en/en_US/bryce/medium`
- Source: <https://brycebeattie.com> (training data released into the public
  domain by the speaker)
- Licence: **Public domain.** Credited here as a courtesy; no attribution is
  required.
- Changes made: looped and encoded as above.
