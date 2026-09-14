function coilName = mapCvsCoilToPge2Coil(coilLabel)
% =========================================================================
% mapCvsCoilToPge2Coil
% =========================================================================
%
% PURPOSE
% -------
% Map a gradient coil label parsed from a .cvs filename into a coil name
% recognised by pge2.opts(...).
%
% INPUT
% -----
% coilLabel : char or string
%   Raw coil label parsed from the filename, e.g.:
%       'XRMB'
%       'XRMW'
%       'HRMW'
%
% OUTPUT
% ------
% coilName : char
%   pge2-supported coil name
%
% NOTES
% -----
% Adjust this mapping if your local naming differs from pge2's expected
% coil identifiers.
%
% =========================================================================

label = lower(strtrim(char(coilLabel)));

switch label
    case 'xrmb'
        % pge2 does not appear to use 'xrmb' explicitly in your earlier
        % opts table, but it does support 'xrm'. Use that as the closest
        % available model unless you later add a dedicated XRMB entry.
        coilName = 'xrm';

    case 'xrm'
        coilName = 'xrm';

    case 'xrmw'
        coilName = 'xrmw';

    case 'hrmw'
        coilName = 'hrmw';

    case 'whole'
        coilName = 'whole';

    case 'zoom'
        coilName = 'zoom';

    case 'magnus'
        coilName = 'magnus';

    otherwise
        error('mapCvsCoilToPge2Coil:UnknownCoil', ...
            'Unknown or unsupported .cvs coil label for pge2: %s', coilLabel);
end
end