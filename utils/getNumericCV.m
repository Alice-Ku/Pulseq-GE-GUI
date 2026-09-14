function val = getNumericCV(cv, key, defaultVal)
% Return numeric value for a key in the containers.Map, or defaultVal

if nargin < 3
    defaultVal = NaN;
end

if isKey(cv, key)
    raw = cv(key);

    % Remove stray commas if ever present
    raw = strrep(raw, ',', '');

    val = str2double(raw);
    if isnan(val)
        val = defaultVal;
    end
else
    val = defaultVal;
end
end