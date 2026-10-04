#include "sound.h"

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <algorithm>

using Microsoft::WRL::ComPtr;

namespace {

// Longer than this is not a sound effect: cut (and memory stays small).
constexpr DWORD kMaxSeconds = 30;
// Never more sounds at once than this.
constexpr size_t kMaxVoices = 8;

bool ValidName(const std::string& name) {
  return !name.empty() && name.size() <= 64 &&
         std::all_of(name.begin(), name.end(), [](char c) {
           return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
         });
}

}  // namespace

SoundPlayer::~SoundPlayer() {
  for (auto* voice : voices_) voice->DestroyVoice();
  voices_.clear();
  if (master_) master_->DestroyVoice();
  if (audio_) audio_->Release();
  if (started_) MFShutdown();
}

bool SoundPlayer::Start() {
  if (started_ || failed_) return started_;
  // COM is already initialized by main.cpp on this thread.
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
    failed_ = true;
    return false;
  }
  started_ = true;
  if (FAILED(XAudio2Create(&audio_, 0, XAUDIO2_DEFAULT_PROCESSOR)) ||
      FAILED(audio_->CreateMasteringVoice(&master_))) {
    failed_ = true;
    return false;
  }
  // Started on the first play only.
  audio_->StopEngine();
  engine_running_ = false;
  return true;
}

std::wstring SoundPlayer::Directory() {
  if (directory_.empty()) {
    wchar_t path[MAX_PATH];
    const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring exe(path, length);
    directory_ = exe.substr(0, exe.find_last_of(L"\\/") + 1) +
                 L"data\\flutter_assets\\assets\\sounds\\";
  }
  return directory_;
}

const SoundPlayer::Clip* SoundPlayer::Load(const std::string& name) {
  const auto found = clips_.find(name);
  if (found != clips_.end()) return &found->second;
  if (missing_.count(name) || !Start() || failed_) return nullptr;
  missing_.insert(name);  // until it is decoded

  const std::wstring file =
      Directory() + std::wstring(name.begin(), name.end()) + L".mp3";
  if (GetFileAttributesW(file.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return nullptr;
  }
  ComPtr<IMFSourceReader> reader;
  if (FAILED(MFCreateSourceReaderFromURL(file.c_str(), nullptr, &reader))) {
    return nullptr;
  }
  constexpr DWORD kAudio = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE);
  reader->SetStreamSelection(kAudio, TRUE);
  ComPtr<IMFMediaType> wanted;
  if (FAILED(MFCreateMediaType(&wanted))) return nullptr;
  wanted->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  wanted->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  if (FAILED(reader->SetCurrentMediaType(kAudio, nullptr, wanted.Get()))) {
    return nullptr;
  }
  ComPtr<IMFMediaType> actual;
  if (FAILED(reader->GetCurrentMediaType(kAudio, &actual))) return nullptr;
  WAVEFORMATEX* format = nullptr;
  UINT32 format_size = 0;
  if (FAILED(MFCreateWaveFormatExFromMFMediaType(actual.Get(), &format,
                                                 &format_size))) {
    return nullptr;
  }
  Clip clip;
  clip.format.assign(reinterpret_cast<BYTE*>(format),
                     reinterpret_cast<BYTE*>(format) + format_size);
  const DWORD bytes_per_second = format->nAvgBytesPerSec;
  CoTaskMemFree(format);
  if (bytes_per_second == 0) return nullptr;
  const size_t limit = static_cast<size_t>(bytes_per_second) * kMaxSeconds;

  while (clip.pcm.size() < limit) {
    DWORD flags = 0;
    ComPtr<IMFSample> sample;
    if (FAILED(reader->ReadSample(kAudio, 0, nullptr, &flags, nullptr, &sample))) {
      break;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) break;
    BYTE* data = nullptr;
    DWORD length = 0;
    if (SUCCEEDED(buffer->Lock(&data, nullptr, &length))) {
      clip.pcm.insert(clip.pcm.end(), data, data + length);
      buffer->Unlock();
    }
  }
  if (clip.pcm.empty()) return nullptr;
  const auto* wfx = reinterpret_cast<const WAVEFORMATEX*>(clip.format.data());
  clip.pcm.resize((std::min)(clip.pcm.size(), limit) / wfx->nBlockAlign * wfx->nBlockAlign);
  clip.duration_ms = static_cast<int>(clip.pcm.size() * 1000 / bytes_per_second);
  missing_.erase(name);
  return &(clips_[name] = std::move(clip));
}

void SoundPlayer::Preload(const std::set<std::string>& names) {
  for (const auto& name : names) {
    if (ValidName(name)) Load(name);
  }
}

int SoundPlayer::Play(const std::string& name, double volume) {
  if (!ValidName(name)) return 0;
  const Clip* clip = Load(name);
  if (!clip) return 0;
  Reap();
  if (voices_.size() >= kMaxVoices) return 0;
  IXAudio2SourceVoice* voice = nullptr;
  if (FAILED(audio_->CreateSourceVoice(
          &voice, reinterpret_cast<const WAVEFORMATEX*>(clip->format.data())))) {
    return 0;
  }
  XAUDIO2_BUFFER buffer = {};
  buffer.Flags = XAUDIO2_END_OF_STREAM;
  buffer.AudioBytes = static_cast<UINT32>(clip->pcm.size());
  buffer.pAudioData = clip->pcm.data();
  voice->SetVolume(static_cast<float>(std::clamp(volume, 0.0, 1.0)));
  if (FAILED(voice->SubmitSourceBuffer(&buffer))) {
    voice->DestroyVoice();
    return 0;
  }
  if (!engine_running_) {
    if (FAILED(audio_->StartEngine())) {
      voice->DestroyVoice();
      return 0;
    }
    engine_running_ = true;
  }
  voice->Start();
  voices_.push_back(voice);
  return clip->duration_ms;
}

bool SoundPlayer::Reap() {
  voices_.erase(std::remove_if(voices_.begin(), voices_.end(),
                               [](IXAudio2SourceVoice* voice) {
                                 XAUDIO2_VOICE_STATE state;
                                 voice->GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
                                 if (state.BuffersQueued > 0) return false;
                                 voice->DestroyVoice();
                                 return true;
                               }),
                voices_.end());
  if (voices_.empty() && engine_running_) {
    audio_->StopEngine();
    engine_running_ = false;
  }
  return !voices_.empty();
}
