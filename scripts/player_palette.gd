extends RefCounted

## The first eight entries keep their historical index and hex identity.
## Save files store hex values, so additional choices never remap an owner.
const COLORS: Array[Color] = [
	Color("e7ad42"), Color("41c7c6"), Color("af80d1"), Color("9bb85a"),
	Color("6498df"), Color("df7860"), Color("d68eb5"), Color("e2d478"),
	Color("4f653a"), Color("233d76"), Color("bc2941"), Color("ed7027"),
	Color("f2eee2"), Color("737f89"), Color("16796c"), Color("642f80")
]
const NAMES := ["琥珀", "青蓝", "紫罗兰", "草绿", "湛蓝", "赤红", "玫瑰", "米黄",
	"军绿", "海军蓝", "绯红", "橙", "白", "灰", "墨青", "深紫"]
