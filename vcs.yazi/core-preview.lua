-- core-preview.lua
-- Dispatch the upper half of the log preview to the Yazi preset previewer
-- corresponding to the current file. The mapping follows Yazi 26.8.15's
-- shipped previewer categories and is intentionally isolated here.
local M = {}

local function copy_job(job, area)
	local result = {}
	for key, value in pairs(job) do result[key] = value end
	result.area = area
	return result
end

M.copy_job = copy_job

local function extension(path)
	return tostring(path or ""):match("%.([^./\\]+)$")
end

function M.name(job)
	local file = job.file or {}
	local cha = file.cha or {}
	if cha.is_dir then return "folder" end

	local mime = tostring(job.mime or "")
	if mime == "image/vnd.djvu" then return "null" end
	if mime == "image/svg+xml" then return "svg" end
	if mime == "image/avif" or mime == "image/jxl" or mime:match("^image/heic") or mime:match("^image/heif") then
		return "magick"
	end
	if mime:match("^image/") then return "image" end
	if mime:match("^video/") then return "video" end
	if mime == "application/pdf" then return "pdf" end
	if mime:match("^font/") or mime == "application/ms-opentype" then return "font" end
	if mime == "inode/empty" then return "empty" end
	if mime:match("^vfs/") then return "vfs" end
	if mime:match("^trash/") then return "trash" end
	if mime:match("^null/") then return "null" end
	if mime:match("^text/") or mime == "application/mbox" or mime == "application/javascript" or mime == "application/wine-extension-ini" then
		return "code"
	end
	if mime == "application/json" or mime == "application/ndjson" then return "json" end
	if mime == "text/csv" then return "code" end
	if mime:match("^application/") then
		local archive_type = mime:match("^application/(.+)$")
		if archive_type and (archive_type:find("zip", 1, true) or archive_type:find("rar", 1, true) or archive_type:find("7z", 1, true)
			or archive_type:find("tar", 1, true) or archive_type:find("gzip", 1, true) or archive_type:find("xz", 1, true)
			or archive_type:find("zstd", 1, true) or archive_type:find("bzip", 1, true) or archive_type:find("lzma", 1, true)
			or archive_type:find("compress", 1, true) or archive_type:find("archive", 1, true) or archive_type:find("cpio", 1, true)
			or archive_type:find("arj", 1, true) or archive_type:find("xar", 1, true) or archive_type:find("cab", 1, true)
			or archive_type:find("debian", 1, true) or archive_type:find("redhat-package-manager", 1, true)
			or archive_type == "rpm" or archive_type == "android.package-archive"
			or archive_type:find("iso9660", 1, true) or archive_type:find("qemu-disk", 1, true)
			or archive_type:find("apple-diskimage", 1, true) or archive_type:find("virtualbox-vhd", 1, true)
			or archive_type:find("virtualbox-vhdx", 1, true) or archive_type:find("ms-wim", 1, true)) then
			return "archive"
		end
	end

	local ext = extension(file.path or job.path or file.url)
	if ext then
		ext = ext:lower()
		if ext == "appimage" or ext == "img" or ext == "fat" or ext == "ext" or ext == "ext2" or ext == "ext3" or ext == "ext4"
			or ext == "squashfs" or ext == "ntfs" or ext == "hfs" or ext == "hfsx" then
			return "archive"
		end
	end
	return "file"
end

local function invoke(name, job)
	local ok, previewer = pcall(require, name)
	if not ok or type(previewer) ~= "table" or type(previewer.peek) ~= "function" then
		return false, "cannot load Yazi previewer " .. tostring(name)
	end
	local called, err = pcall(previewer.peek, previewer, job)
	if not called then return false, err end
	return true
end

function M.peek(job, area)
	local preview_job = copy_job(job, area or job.area)
	local name = M.name(preview_job)
	local ok, err = invoke(name, preview_job)
	if ok or name == "file" then return ok, err end
	-- A missing optional preset previewer should not erase the file preview.
	return invoke("file", preview_job)
end

function M.seek(job, area)
	local preview_job = copy_job(job, area or job.area)
	local name = M.name(preview_job)
	local ok, previewer = pcall(require, name)
	if not ok or type(previewer) ~= "table" or type(previewer.seek) ~= "function" then return end
	pcall(previewer.seek, previewer, preview_job)
end

return M
