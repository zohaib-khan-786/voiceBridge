# Whisper Model Files

This directory should contain the Whisper ONNX model files for local speech-to-text.

## Required Files

Place the following files in this directory:

1. **encoder_model_q4f16.onnx** (~30 MB)
   - The Whisper encoder model that processes audio features
   
2. **decoder_model_merged_q4f16.onnx** (~30 MB)
   - The Whisper decoder model that generates transcriptions

## How to Obtain These Files

You should have received these files separately. They are quantized versions of OpenAI's Whisper model converted to ONNX format for efficient on-device inference.

## File Placement

**IMPORTANT:** Copy both `.onnx` files directly into this directory:
```
app/src/main/assets/whisper_model/
├── encoder_model_q4f16.onnx
└── decoder_model_merged_q4f16.onnx
```

## What These Models Do

- **Encoder**: Converts audio mel-spectrogram features into a continuous representation
- **Decoder**: Generates text transcriptions from the encoder's output

## Performance

- **Processing Time**: ~500ms per 5-second audio chunk
- **Memory Usage**: ~150 MB during inference
- **Accuracy**: Comparable to Whisper-tiny for 99+ languages
- **Privacy**: 100% on-device, no data sent to cloud

## Supported Languages

The models support 99+ languages including:
- Urdu (ur) - Primary target for this app
- English (en)
- Arabic (ar)
- Hindi (hi)
- French (fr)
- Spanish (es)
- German (de)
- Turkish (tr)
- Chinese (zh)
- Russian (ru)
- Portuguese (pt)
- Japanese (ja)
- Korean (ko)
- Italian (it)
- Farsi/Persian (fa)
- Bengali (bn)
- Dutch (nl)
- Polish (pl)

And many more!

## Build Process

The Android build system will automatically bundle these models into the APK. Make sure both files are present before building the app.

## Troubleshooting

**Error: "Failed to initialize Whisper models"**
- Ensure both .onnx files are present in this directory
- Check that files are not corrupted (should be ~30 MB each)
- Verify file names match exactly: `encoder_model_q4f16.onnx` and `decoder_model_merged_q4f16.onnx`

**Out of Memory Errors**
- The models require ~150 MB of RAM
- Ensure your device has at least 2 GB of total RAM
- Close other apps before using voice features
