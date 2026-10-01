import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A Windows job object holding one agent and everything it starts
/// (MVP spec §3.5): stopping the agent ends the whole tree at once, and if
/// Mikky itself ends, Windows ends the agents with it (kill on close).
///
/// A process joins the job right after it starts, before Mikky sends it
/// anything, so the agent's own children (started after `initialize`) are
/// born inside it.
class ProcessJob {
  ProcessJob._(this._handle);

  /// A job for [pid], or null off Windows or if Windows refuses.
  static ProcessJob? forProcess(int pid) {
    if (!Platform.isWindows) return null;
    final job = _createJobObject(nullptr, nullptr);
    if (job == nullptr) return null;
    final info = calloc<Uint8>(_extendedLimitInfoSize);
    try {
      (info + _limitFlagsOffset).cast<Uint32>().value = _killOnJobClose;
      if (_setInformationJobObject(job, _extendedLimitInformation, info.cast(), _extendedLimitInfoSize) == 0) {
        _closeHandle(job);
        return null;
      }
    } finally {
      calloc.free(info);
    }
    final process = _openProcess(_processSetQuota | _processTerminate, 0, pid);
    if (process == nullptr) {
      _closeHandle(job);
      return null;
    }
    final ok = _assignProcessToJobObject(job, process) != 0;
    _closeHandle(process);
    if (!ok) {
      _closeHandle(job);
      return null;
    }
    return ProcessJob._(job);
  }

  Pointer<Void>? _handle;

  /// Ends every process of the job, then lets the job go.
  void terminate() {
    final h = _handle;
    if (h == null) return;
    _terminateJobObject(h, 1);
    close();
  }

  /// Lets the job go. With kill on close, its processes end too.
  void close() {
    final h = _handle;
    if (h == null) return;
    _handle = null;
    _closeHandle(h);
  }
}

// JOBOBJECT_EXTENDED_LIMIT_INFORMATION on 64-bit Windows: 144 bytes,
// BasicLimitInformation.LimitFlags at byte 16.
const _extendedLimitInfoSize = 144;
const _limitFlagsOffset = 16;
const _extendedLimitInformation = 9;
const _killOnJobClose = 0x2000;
const _processTerminate = 0x0001;
const _processSetQuota = 0x0100;

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createJobObject = _kernel32
    .lookupFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>), Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>)>(
      'CreateJobObjectW',
    );
final _setInformationJobObject = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32), int Function(Pointer<Void>, int, Pointer<Void>, int)>(
      'SetInformationJobObject',
    );
final _openProcess = _kernel32.lookupFunction<Pointer<Void> Function(Uint32, Int32, Uint32), Pointer<Void> Function(int, int, int)>(
  'OpenProcess',
);
final _assignProcessToJobObject = _kernel32
    .lookupFunction<Int32 Function(Pointer<Void>, Pointer<Void>), int Function(Pointer<Void>, Pointer<Void>)>('AssignProcessToJobObject');
final _terminateJobObject = _kernel32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>(
  'TerminateJobObject',
);
final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle');
