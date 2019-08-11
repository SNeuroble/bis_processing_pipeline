/usr/local/bin/matlab -nodesktop >slicetime.out <<EOF

% Slicetime correction template file (080919)
%The old script and this use slightly different rounding
%output intensities may be off be 1

path('Xsoftware_path',path);
basedir = ['Xfunc_dir'];
study_list = ['001' ;];
nslices = Xnslices; 
tr = Xtr; 

for i = 1:size(study_list,1)

    %may need to change the next two lines depending on your needs
    zipped = dir('*.nii.gz')
    gunzip({zipped.name})
    filter_expression=sprintf('sub-pixar%s.+.nii$',deblank(study_list(i,:))) 
    f=spm_select('FPList',deblank(basedir),Xfilter_expression)
    disp(f);
    mrrc_slicetime_wrapper_Xslice_acquisition_direction(f,nslices,tr);
end

quit
EOF





