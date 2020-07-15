#!/bin/bash
# THIS IS NOT USED ANYMORE - leaving here bc Link's script probably still relies on this

# Make study-specific edits - subject-specific edits will be made later in the main

setupfile=$out_path/study_setupfile_${dataset_name}.xmlg
cp $templates_path/study_setupfile_template.xmlg $setupfile

sed -i "s#Xdataset_name#${dataset_name}#g" $setupfile
sed -i "s#Xreference_img#${reference_img}#g" $setupfile
sed -i "s#Xwm_csf_img#${wm_csf_img}#g" $setupfile
sed -i "s#Xidentity_matrix#${identity_mat}#g" $setupfile
sed -i "s#Xtr#${tr}#g" $setupfile
sed -i "s#Xn_slices#${n_slices}#g" $setupfile
sed -i "s#Xn_frames#${n_frames}#g" $setupfile
sed -i "s#Xoutput_dir#${results_dir}#g" $setupfile
sed -i "s#Xparcellation#${parcellation}#g" $setupfile
sed -i "s#Xtemporal_sigma#${temporal_sigma}#g" $setupfile
sed -i "s#Xgsr#${do_GSR}#g" $setupfile



