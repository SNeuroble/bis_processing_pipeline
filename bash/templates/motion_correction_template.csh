/usr/local/bin/matlab -nodesktop > motioncorrection.out <<EOF

% Motion correction template file (080919)
%nii and hdr/img may have different parameters due to how spm reads the header matrix for nifti vs non-nifti
%old script uses linear interpolation
%naming output of .mat motion parameters is slightly different

path('Xsoftware_path',path);
use_old_flags=Xuse_old_moco;
use_middle_run=0;

basedir = ['Xfunc_dir'];
study_list = ['001' ;];

for i = 1:size(study_list,1)

    %may need to change the next two lines depending on your needs
    filter_expression=sprintf('Xfilter_expr',deblank(study_list(i,:)));
    parameter_dir=sprintf('%s/%sXmotion_dir/',basedir,deblank(study_list(i,:)));
    f=spm_select('FPList',deblank(basedir),filter_expression);
    if(use_middle_run)
	mid=ceil(size(f,1)/2);
	f=[ f(mid,:) ; f(1:(mid-1),:) ; f((mid+1):end,:) ]
    end
    if ~isempty(f)
        mrrc_motioncorrection_wrapper(f,use_old_flags,parameter_dir);
    end

end

% test this part
for i = 1:size(study_list,1)
filter_expression=sprintf('Xfilter_expr',deblank(study_list(i,:)));
    parameter_dir=sprintf('%s/%sXmotion_dir/',basedir,deblank(study_list(i,:)));
    f=spm_select('FPList',deblank(basedir),filter_expression);

    tmp=load_nii(f);
    all_imgs(:,:,:,i)=tmp.img;
end

mean_img=mean(all_imgs,4);
tmp.img=mean_img;
save_nii(Xmean_func_file,tmp.img);


quit

EOF













