package com.smartmpc.app

object WebRtcMediaCommandBridge {
    @Volatile
    private var listener: ((String) -> Unit)? = null

    fun setListener(commandListener: (String) -> Unit) {
        listener = commandListener
    }

    fun clearListener(commandListener: (String) -> Unit) {
        if (listener === commandListener) {
            listener = null
        }
    }

    fun dispatch(command: String) {
        listener?.invoke(command)
    }
}
