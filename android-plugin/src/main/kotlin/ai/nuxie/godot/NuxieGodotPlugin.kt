package ai.nuxie.godot

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.ConcurrentLinkedQueue

/** Value-only queue: Godot drains on its own thread, never from a native callback. */
class NuxieGodotPlugin(godot: Godot) : GodotPlugin(godot) {
  private val messages = ConcurrentLinkedQueue<String>()
  private var bridge: NuxieGodotBridge? = null
  override fun getPluginName() = "NuxieGodot"

  @UsedByGodot
  fun dispatch(json: String) {
    val host = activity ?: return
    host.runOnUiThread {
      val current = bridge ?: NuxieGodotBridge(host, object : NuxieGodotBridge.Callback {
        override fun onMessage(message: String) { messages.add(message) }
      }).also { bridge = it }
      current.dispatch(json)
    }
  }

  @UsedByGodot
  fun pop_message(): String = messages.poll() ?: ""

  override fun onMainDestroy() {
    bridge?.invalidate()
    bridge = null
    messages.clear()
    super.onMainDestroy()
  }
}
