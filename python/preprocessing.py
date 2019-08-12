import glob,os,sys
import subprocess
import re


path = '.'
matlab='/usr/bin/matlab'
nslices = 32; 
tr = 2; 
slice_time = 'ascending' # [ascending descending descending_interleaved] 
use_old_flags= 0
dataset_name = "tom"
identity_mat = '/data_dustin/dataset/scripts/i.matr'
skip_frames_on = 0
block_def_time = 1 #Block Definition Time (1=seconds, 0 =frames)
afni_norm=0                    
glm_delay_time=2               
glm_rise_time = 4              
glm_falltime=6                 
glm_shoot=0.2                  
glm_peak = 1.0                 
ply_drift=3                    
parcellation = '/data_dustin/dataset/scripts/shen_1mm_268_parcellation.nii'
mask_level = 0.05
 

files= os.walk(path)
subprocess.call(["source","/data1/software/bioimagesuite35/setpaths.csh"])

def main():
    for folder in files:
        if(any(char.isdigit() and 'anat' in folder[0] for char in folder[0])): # anatomical
            anat_dir = folder[0]
            func_dir = folder[0].replace("anat","func") 
            sub_ID = re.findall('\d+',func_dir)[0]
            print('stp 1: skull stripping for subject %s'%sub_ID)
            step1(anat_dir)

            print('stp 2: non-linear registeration for subject %s'%sub_ID)
            step2(anat_dir)		

                            
            print('step3: slice time correction')
            step3(func_dir)

            print('step4: motion correction')
            step4(func_dir)

            print('step5,6: aquiring correlation matrices')
            step56(anat_dir,func_dir)

 
def step1(anat_dir):
    for file in os.listdir(anat_dir):# step 1: skull stripping
        if file.endswith(".gz") and "optiBET" not in file:
            print(os.path.join(anat_dir,file))
            subprocess.call(["/data1/software/optiBET.sh","-i",os.path.join(anat_dir,file)])

def step2(anat_dir):
    for file in os.listdir(anat_dir): # step 2: non-linear register to common space
        if file.endswith("optiBET_brain.nii.gz"):
            f = open("nonlinear_setup","w")
            f.write("set inputlist(1) {/data1/software/bioimagesuite35/images/MNI_T1_1mm_stripped.nii.gz}\n")
            f.write("set inputlist(2) {"+os.path.join(folder[0],file)+"}\n")
            f.write("set inputlist(3) {*ignore*}\nset inputlist(4) {*ignore*}\nset inputlist(5) {*ignore*}\nset outputsuffix {map.grd}\nset logsuffix \"results\"\nset cmdline \"bis_nonlinearbrainregister.tcl\"\n")
            f.close()
            subprocess.call(["bis_makebatch.tcl","-odir",anat_dir,"-setup","nonlinear_setup","-makefile","nonlinear.make"])
            subprocess.call(["make","-f","nonlinear.make","-j","3"])

def step3(func_dir):
    for file in os.listdir(func_dir): # step 3: slice time correction
        if file.endswith(".nii.gz"):
            f = open("slicetime_correction_UPSM.csh","w")	
            f.write(matlab+" -nodesktop >slicetime.out <<EOF\n")
            f.write("path('/data1/software/spm8',path)\n")
            f.write("gunzip('"+os.path.join(func_dir,file)+"')\n")
            f.write("filter_expression=sprintf('"+file.replace('.gz','')+"$')\n")
            f.write("f=spm_select('FPList',deblank('"+func_dir+"'),filter_expression)\n")
            if(slice_time == "ascending"):
                f.write("mrrc_slicetime_wrapper_ascending(f,"+str(nslices)+","+str(tr)+")\n")
            elif(slice_time=="descending"):
                f.write("mrrc_slicetime_wrapper_descending(f,"+str(nslices)+","+str(tr)+")\n")
            elif(slice_time=="descending_interleaved"):
                    f.write("mrrc_slicetime_wrapper_descending_interleaved(f,"+str(nslices)+","+str(tr)+")\n")
            f.write("quit\n")
            f.write("EOF")
            f.close()
            subprocess.call(["sh","slicetime_correction_UPSM.csh"])

def step4(func_dir):
    for file in os.listdir(func_dir): # step 4: motion correction
        if file.endswith(".nii") and file.startswith('A') and 'R_' not in file:
            f = open("moco_session3.csh","w")	
            f.write(matlab+" -nodesktop >motioncorrection.out <<EOF\n")
            f.write("path('/data1/software/spm8',path)\n")
            f.write("filter_expression=sprintf('"+file+"$')\n")
            #f.write("filter_expression=\""+file+"$\"\n")
            f.write("parameter_dir='"+func_dir+"/realign/'\n")
            f.write("f=spm_select('FPList',deblank('"+func_dir+"'),filter_expression)\n")
            f.write("if ~isempty(f)\n")
            f.write("mrrc_motioncorrection_wrapper(f,"+str(use_old_flags)+",parameter_dir)\n");
            f.write("end\n")
            f.write("quit\n")
            f.write("EOF")
            f.close()
            subprocess.call(["sh","moco_session3.csh"])

def step56(anat_dirfunc_dir):
    for file in os.listdir(func_dir): # step 5: linear registeration to skull-stripped anatomical image
        if file.endswith(".hdr"):
            subprocess.call(["pxtonifti.tcl",os.path.join(func_dir,file)])
        if file.endswith(".nii") and file.startswith("mean"):
            mean_moco_file = file
        for file in os.listdir(anat_dir):
            if file.endswith(".nii.gz") and "optiBET_brain" in file and "mask" not in file and "weight" not in file :
                        print('step 6: linear registeration to skull-stripped anatomical image %s'%file)
                        anat_optiBET = file
                        f = open("linear_registeration_setup","w")
                        f.write("set inputlist(1) {\n"+os.path.join(anat_dir,file)+"\n}\n")
                        f.write("set inputlist(2) {\n"+os.path.join(func_dir,mean_moco_file)+"\n}\n")
                        f.write("set inputlist(3) {\n*ignore*\n}\nset inputlist(4) {\n*ignore*\n}\nset inputlist(5) {\n*ignore*\n}\nset outputsuffix {\n_linear.matr\n}\nset logsuffix \"results\"\n\nset cmdline \"bis_linearintensityregister.tcl\"\n")
                        f.close()
                        subprocess.call(["bis_makebatch.tcl","-odir",func_dir,"-setup","linear_registeration_setup","-makefile","linearregisteration.make"])
                        subprocess.call(["make","-f","linearregisteration.make","-j","3"])
        for file in os.listdir(anat_dir):
            if file.endswith('_3rdpass.grd') and file.startswith('MNI_'):
                thirdpass_img = file
        for file in os.listdir(func_dir):
            if file.endswith('_linear.matr') and 'mean' in file:
                mean_matr = file
            if file.endswith('_bold.nii') and file.startswith('R_'):
                fourd_img = file
        for file in os.listdir(os.path.join(func_dir,'realign')):    
            if file.endswith('_bold_hiorder.mat') and file.startswith('REALIGN_'):
                realign_mat = os.path.join('realign',file)
        for file in os.listdir(func_dir): # step 6: build connectivity matrix
            f = open("subj.xmlg","w")
            f.write("#BioImageSuite Study Description File v2\n")
            f.write("#-----------------------------------------------------\n")
            f.write("#Study Title\n")
            f.write(dataset_name+"\n")
            f.write("#Subject ID\n") 
            f.write(re.findall('\d+',func_dir)[0]+"\n")
            f.write("#-----------------------------------------------------\n")
            f.write('#Anatomical Data\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Reference Brain\n')
            f.write('/data1/software/bioimagesuite35/images/MNI_T1_1mm_stripped.nii.gz\n')
            f.write('#Reference Gray/White/CSF Map\n')
            f.write('/data_dustin/dataset/example/MNI_1mm_WM_CSF_erode.nii.gz\n')
            f.write('#3D Anatomical Image\n')
            f.write(os.path.join(anat_dir,anat_optiBET)+'\n')
            f.write('#Conventional Image\n\n')
            f.write('#Ref-> 3D Anatomical Transformation \n')
            f.write(os.path.join(anat_dir,thirdpass_img)+'\n')
            f.write('#3D Anatomical -> Conventional Transformation\n')
            f.write(identity_mat+'\n')
            f.write('#Conventional -> EPI Transformation\n')
            f.write(os.path.join(func_dir,mean_matr)+'\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Basic Parameters\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Session ID\n')
            f.write('sess-T1\n')
            f.write('#Session Description\n')
            f.write('sess_movies\n')
            f.write('#Number of Runs\n')
            f.write('1\n')
            f.write('#Number of Tasks\n')
            f.write('0\n')
            f.write('#Number of Outcomes\n')
            f.write('0\n')
            f.write('#Repetition Time (TR)\n')
            f.write(str(tr)+'\n')
            f.write('#Number of Slices\n')
            f.write(str(nslices)+'\n')
            f.write('#Number of Frames\n\n')

            f.write('#Skip Frames On\n')
            f.write(str(skip_frames_on)+'\n')
            f.write('#Frames to Skip\n\n')

            f.write('#-----------------------------------------------------\n')
            f.write('#Outputs Files/Locations\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#XML Output File\n\n')

            f.write('#XML Output Directory\n\n')

            f.write('#Data Output Directory\n')
            f.write(os.path.join(func_dir,'result')+'\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Runs\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Run 1 (first line=4D Image, second line=Matrix with Motion Parameters)\n')
            f.write(os.path.join(func_dir,fourd_img)+'\n')
            f.write(os.path.join(func_dir,realign_mat)+'\n')
            f.write('No Skip\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Tasks\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Blocks\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Block Definition Time (1=seconds, 0 =frames)\n')
            f.write(str(block_def_time)+'\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Outcomes\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#GLM Processing and AFNI Integration\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Ensure Inputs are NIFTI\n')
            f.write('ensurenifti : 0\n')
            f.write('#Delete Temporary Files\n')
            f.write('deletetemp : 1\n')
            f.write('#Mask Level (% of max intensity)\n')
            f.write('masklevel : 0.05\n')
            f.write('#HRF Mode -- one of wav, gamma, doublegamma, triplegamma spm\n')
            f.write('hrfmode : wav\n')
            f.write('#Use AFNI Waver; if 0 use internal code which is cleaner/faster etc\n')
            f.write('useafniwaver : 0\n')
            f.write('#Use AFNI Commands for intensity normalization; if 0 use internal code which is cleaner/faster etc\n')
            f.write('useafninormalize : '+str(afni_norm)+'\n')
            f.write('#GLM Delaytime\n')
            f.write('delaytime : '+str(glm_delay_time)+'\n')
            f.write('#GLM Risetime\n')
            f.write('risetime : '+str(glm_rise_time)+'\n')
            f.write('#GLM Falltime\n')
            f.write('falltime : '+str(glm_falltime)+'\n')
            f.write('#GLM Undershoot\n')
            f.write('undershoot : '+str(glm_shoot)+'\n')
            f.write('#GLM Peak\n')
            f.write('peak : '+str(glm_peak)+'\n')
            f.write('#Polynomial Drift\n')
            f.write('polort : '+str(ply_drift)+'\n')
            f.write('#Output Baseline Coefficientts\n')
            f.write('bout : 0\n')
            f.write('#Output F-Statistics\n')
            f.write('fout : 0\n')
            f.write('#Output R^2-Statistics\n')
            f.write('rout : 0\n')
            f.write('#Output T-Statistics\n')
            f.write('tout : 0\n')
            f.write('#Output Residual Time Series\n')
            f.write('saveresidual : 0\n')
            f.write('#Output Drift Beta Maps\n')
            f.write('savedriftbeta : 0\n')
            f.write('#Output Sample Variance Map\n')
            f.write('vout : 0\n')
            f.write('#GLM Single Run Output\n')
            f.write('glmsinglerunoutput : 0\n')
            f.write('#GLM Regress Motion Parameters\n')
            f.write('glmregressmotion : 0\n')
            f.write('#Rate GLM Terms\n')
            f.write('numrateterms : 1\n')
            f.write('#Rate GLM Global Drift\n')
            f.write('rateglobal : 0\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Resting State Connectivity Extra Inputs\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#VOI Definition\n')
            f.write(parcellation+'\n')
            f.write('#VOI Definition Space (Reference,Anatomical,Conventional,Functional)\n')
            f.write('Reference\n')
            f.write('#Inverse Reference Transformation\n')
            f.write(os.path.join(anat_dir,'Inverse_'+thirdpass_img)+'\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Connectivity Parameters\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Mask Level (% of max intensity)\n')
            f.write('masklevel : '+str(mask_level)+'\n')
            f.write('#Polynomial Drift\n')
            f.write('driftpol : 3\n')
            f.write('# Slice Mean Removal \n')
            f.write('slicemeanremoval : 0\n')
            f.write('# Volume Mean Removal \n')
            f.write('volumemeanremoval : 1\n')
            f.write('#Raw Correlation\n')
            f.write('rawcorrelation : 0\n')
            f.write('#Z Transform\n')
            f.write('ztransform : 0\n')
            f.write('#Process Runs Individually\n')
            f.write('individualruns : 1\n')
            f.write('#Temporal Smoothing Sigma (Frames)\n')
            f.write('temporalsigma : 1\n')
            f.write('#Intrinsic Connectivity Threshold\n')
            f.write('threshold : 0.0\n')
            f.write('#Intrinsic Connectivity Range\n')
            f.write('range : Both\n')
            f.write('#Intrinsic Connectivity Mode\n')
            f.write('mode : Sqr\n')
            f.write('#Use VOI Image as mask For Intrinsic Connectivity\n')
            f.write('usermask : 1\n')
            f.write('#Preprocess (Eliminate Motion Parameters)\n')
            f.write('usemotionparams : 1\n')
            f.write('#Preprocess (Eliminate CSF/White Matter Mean)\n')
            f.write('usecsfmean : 1\n')
            f.write('#Preprocess (remove high motion frames)\n')
            f.write('scrub : 0\n')
            f.write('#Scrub threshold\n')
            f.write('scrub_threshold : 0.3\n')
            f.write('#skip the frames before and after high motion frame\n')
            f.write('skipbeforeandafter : 1\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Extra GLM Parameters Parameters\n')
            f.write('#-----------------------------------------------------\n')
            f.write('#Use External Matrix File\n')
            f.write('useexternalmatrix : 0\n')
            f.write('#External Matrix FileName\n')
            f.write('externalmatrixfilename : \n')
            f.write('#Do Convolution with HRF\n')
            f.write('doconvolution : 1\n')
            f.close()
            subprocess.call(["bis_fmrisetup.tcl","subj.xmlg","matrix",func_dir])
main()                   
