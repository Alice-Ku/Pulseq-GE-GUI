function cv = parseCvsKeyValueFile(cvsFile)
% Parse a GE-style .cvs file into a containers.Map of cvname -> value string

fid = fopen(cvsFile, 'r');
if fid < 0
    error('parseCvsKeyValueFile:OpenFailed', 'Cannot open file: %s', cvsFile);
end

cleanupObj = onCleanup(@() fclose(fid));

cv = containers.Map('KeyType', 'char', 'ValueType', 'char');

lineNum = 0;
while true
    tline = fgetl(fid);
    if ~ischar(tline)
        break;
    end
    lineNum = lineNum + 1;

    tline = strtrim(tline);
    if isempty(tline)
        continue;
    end

    % Skip obvious header line(s)
    if contains(lower(tline), 'cvfile') || contains(lower(tline), 'cvname cvvalue')
        continue;
    end

    % Split on whitespace
    parts = regexp(tline, '\s+', 'split');

    % Expect at least:
    %   cvname  cvvalue  exist_flag  fix_flag
    if numel(parts) < 2
        continue;
    end

    key = strtrim(parts{1});
    val = strtrim(parts{2});

    if ~isempty(key)
        cv(key) = val;
    end
end
end