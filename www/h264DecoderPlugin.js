var exec = require('cordova/exec');

var PLUGIN_NAME = 'H264DecoderPlugin';

var H264DecoderPlugin = {
  initialize: function(success, error){
    exec(success, error, PLUGIN_NAME, "initialize", []);
  },
  setCallback: function(decode, error){
    exec(function (width, height, buffer) {
      decode(width, height, buffer)
    }, error, PLUGIN_NAME, "setCallback", []);
  },
  decode: function(frameArray, success, error){
    exec(success, error, PLUGIN_NAME, "decode", [frameArray]);
  },
  invalidate: function(success, error){
    exec(success, error, PLUGIN_NAME, "invalidate", []);
  }
}

module.exports = H264DecoderPlugin;