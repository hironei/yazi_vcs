return function(t)
	local preview = require("core-preview")

	t.eq(preview.name({ file = { cha = { is_dir = true } }, mime = "inode/directory" }), "folder", "directories use the folder previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "text/plain" }), "code", "text uses the code previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/json" }), "json", "JSON uses the JSON previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "image/svg+xml" }), "svg", "SVG uses the SVG previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "image/png" }), "image", "ordinary images use the image previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/pdf" }), "pdf", "PDF uses the PDF previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/zip" }), "archive", "archives use the archive previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/iso9660-image" }), "archive", "disk images use the archive previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "inode/empty" }), "empty", "empty files use the empty previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/octet-stream", path = "thing.appimage" }), "archive", "AppImage uses the archive previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/octet-stream", path = "disk.img" }), "archive", "disk image extensions use the archive previewer")
	t.eq(preview.name({ file = { cha = {} }, mime = "application/octet-stream", path = "unknown.bin" }), "file", "unknown files use the fallback previewer")

	local job = { area = { w = 20, h = 10 }, file = { path = "/repo/a.txt" }, mime = "text/plain", skip = 2 }
	local copied = preview.copy_job(job, { w = 20, h = 5 })
	t.eq(copied.area.h, 5, "copy_job replaces only the preview area")
	t.eq(copied.file.path, job.file.path, "copy_job preserves the file")
	t.eq(copied.skip, 2, "copy_job preserves the preview offset")
end
