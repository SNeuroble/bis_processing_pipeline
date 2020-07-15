Xmatlab_path -nodesktop > Xlog_dir/slicetime.out <<EOF

% Slicetime correction template file (SMN042820, based on v080919)
% Each scan will be corrected separately
% v080919 was updated so values may slightly differ from older (pre 080919) versions

path('Xsoftware_path',path);
study_list = {Xstudy_list};
nslices = Xnslices; 
tr = Xtr; 

for i = 1:length(study_list)

    this_scan=study_list{i};
    fprintf(['Doing slicetime for ',this_scan,'\n']);

    % try to gunzip if no .nii but .nii.gz exists - due to a couple steps in the main pipeline, the string "this_scan" will always end in .nii even if the file ends in .gz
    if ~isfile(this_scan)
        if isfile([this_scan,'.gz'])
            gunzip([this_scan,'.gz']);
        else
            error(['Missing file ',this_scan,'!\n'])
        end
    end

    [this_dir,this_name,this_ext] = fileparts(this_scan);
    f=spm_select('FPList',this_dir,['^',this_name,this_ext,'$']);
    mrrc_slicetime_wrapper_Xslice_acquisition_direction(f,nslices,tr);

end

quit
EOF





