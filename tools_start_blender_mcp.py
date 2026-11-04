import bpy, addon_utils
addon_utils.enable("blender_mcp", default_set=True, persistent=True)

def _start():
    try:
        bpy.ops.blendermcp.start_server()
        print("MCP_SERVER_STARTED", bpy.context.scene.blendermcp_port)
    except Exception as e:
        print("MCP_START_FAIL", e)
    return None

bpy.app.timers.register(_start, first_interval=1.0)
print("MCP_BOOTSTRAP_READY")
