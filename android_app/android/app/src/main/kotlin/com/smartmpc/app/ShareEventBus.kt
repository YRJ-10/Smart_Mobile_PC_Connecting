package com.smartmpc.app

object ShareEventBus {
    var listener: ((Int) -> Unit)? = null
    
    fun notifyLinksQueued(count: Int) {
        listener?.invoke(count)
    }
}
