return function(t)
	if t.is_windows then
		t.eq(t.to_file_url("C:\\tmp\\repo"), "file:///C:/tmp/repo", "Windows file URL converts single backslashes")
	else
		t.eq(t.to_file_url("/tmp/repo"), "file:///tmp/repo", "POSIX file URL remains stable")
	end
end
