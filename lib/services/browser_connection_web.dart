import 'dart:js_interop';

@JS('navigator.onLine')
external bool get _online;

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction callback);

bool get browserIsOnline => _online;
void watchBrowserOnline(void Function() callback) {
  _addEventListener('online', ((JSAny? event) => callback()).toJS);
}
