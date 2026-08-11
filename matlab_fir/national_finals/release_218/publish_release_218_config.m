% Publish the board-verified 218-LUT configuration as machine-readable JSON.

clearvars;
script_dir = fileparts(mfilename('fullpath'));
nf_dir = fileparts(script_dir);
addpath(nf_dir);

config = nf_release_218_config();
json_text = jsonencode(config, PrettyPrint=true);
output_path = fullfile(script_dir, 'nf_release_218_config.json');
fid = fopen(output_path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not open release JSON: %s', output_path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', json_text);
fprintf('NF_RELEASE_218_CONFIG_PASS: %s\n', output_path);
