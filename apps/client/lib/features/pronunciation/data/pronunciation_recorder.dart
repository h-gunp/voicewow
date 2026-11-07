export 'pronunciation_recorder_contract.dart';
export 'pronunciation_recorder_stub.dart'
    if (dart.library.io) 'pronunciation_recorder_native.dart'
    if (dart.library.js_interop) 'pronunciation_recorder_web.dart';
