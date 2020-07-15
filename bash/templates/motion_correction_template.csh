Xmatlab_path -nodesktop > Xlog_dir/motioncorrection.out <<EOF

% Motion correction template file (SMN042820, based on 080919)
% All functional scans for a subject will be realigned to the reference functional scan (first or middle) and the mean of that scan will also be created
%nii and hdr/img may have different parameters due to how spm reads the header matrix for nifti vs non-nifti
%old script uses linear interpolation
%naming output of .mat motion parameters is slightly different

path('Xsoftware_path',path);
use_old_flags=Xuse_old_moco;
use_middle_run=Xmoco_to_middle_run;

basedir = 'Xfunc_dir';
parameter_dir='Xparameter_dir';

fprintf(['Doing motion correction for ',basedir,'\n']);

f=spm_select('FPList',deblank(basedir),'^Xslicetime_prefix.*nii$');

if(use_middle_run)
	mid=ceil(size(f,1)/2);
    f=[ f(mid,:) ; f(1:(mid-1),:) ; f((mid+1):end,:) ]
end

if ~isempty(f)
    mrrc_motioncorrection_wrapper(f,use_old_flags,parameter_dir);
end

quit

EOF













