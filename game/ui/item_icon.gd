class_name ItemIcon
extends Control
## One art source for the hotbar, inventory, recipe book and held-item renderer.
var item_id: int = 1
var amount: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(48,48)

func _draw() -> void:
	if item_id <= 0: return
	var texture: Texture2D = BlockAtlas.icon_texture(item_id) if BlockDB.is_block(item_id) else ItemGlyphs.texture_for(item_id)
	var available = minf(size.x,size.y)-10.0
	var extent = maxf(16.0,floorf(available/16.0)*16.0)
	var origin = ((size-Vector2.ONE*extent)*.5).floor()
	draw_texture_rect(texture,Rect2(origin,Vector2.ONE*extent),false)
	if amount > 1:
		var label = str(amount)
		var width = SlopSkin.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var p = Vector2(size.x-width-3,size.y-3)
		draw_string(SlopSkin.font,p+Vector2(1,2),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.BLACK)
		draw_string(SlopSkin.font,p,label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
