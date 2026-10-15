shader_type canvas_item;
render_mode blend_mix;

// 受击闪白。像素画做受击反馈的标准做法：
// 把颜色往目标色混合，而不是改 modulate ——
// modulate 是乘法，暗色像素乘什么都还是暗的，做不出"亮一下"的效果。
//
// 用法：给的材质设 flash = 1.0，然后在 0.1~0.15 秒内把 flash 衰减到 0。
// 与美术交付的"受击特效 spritesheet"不冲突，两者可以叠加。

// 闪白强度：0 = 原样，1 = 完全变成 flash_color
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 闪白颜色。默认白；需要偏红/偏青的受击色时改这里
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	// 乘 alpha 是为了不把全透明像素也点亮相（否则精灵会出现方框底色）
	col.rgb = mix(col.rgb, flash_color, flash * col.a);
	COLOR = col;
}
