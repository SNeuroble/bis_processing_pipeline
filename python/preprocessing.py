import glob,os,sys
import subprocess
import re
import math

path = '/data17/mri_group/abby_data/DimensionalSuperData/sample/'
MyOut = subprocess.Popen(['which', 'matlab'], 
                    stdout=subprocess.PIPE, 
                            stderr=subprocess.STDOUT)
stdout,stderr = MyOut.communicate()
matlab = stdout.strip()
nslices = 75; 
tr = 1; 
slice_time = 'none' # [ascending descending descending_interleaved none] 
use_old_flags= 0
dataset_name = "dsd"
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
skip_frame_num = '0 7'
temporalsigma = 1.55

files= os.walk(path)
#subprocess.call(["source","/data1/software/bioimagesuite35/setpaths.csh"])

def main():
    for folder in files:
        if(any(char.isdigit() and 'anat' in folder[0] for char in folder[0])): # anatomical
            anat_dir = folder[0]
	    func_dir = folder[0].replace("anat","func") 
            sub_ID = re.findall('p\w\d+',func_dir)[0]
            subj_folder =anat_dir.replace("/anat","");
            subj_sessinfo = folder[0].replace("anat",sub_ID+"_constable_seriesinfo")
	    print(subj_sessinfo)
            #out =subprocess.call(["grep", "T1W_MPR", "*.txt", "|", "cut", "-d", ".", "-f", "1"]);
	    if not os.path.exists(os.path.join(subj_folder,'code')):
	        os.mkdir(os.path.join(subj_folder,'code'))
	    session_file=os.path.join(subj_folder,'code','session.txt')
	    f = open(session_file, "w")
            out =subprocess.call(["grep", "-r","T1W_MPR",os.path.join(subj_folder,subj_sessinfo)],stdout=f);
            data=""
	    
            with open(session_file, 'r') as file:
                    data = file.read().replace('\n', '')
                    tokens = data.split("/")
                    print(tokens[8].split(".txt")[0])
            print('stp 1: skull stripping for subject %s'%sub_ID)
            step1(anat_dir,tokens[8].split(".txt")[0])
	    
            print('stp 2: non-linear registration for subject %s'%sub_ID)
            step2(anat_dir,subj_folder)        
            if slice_time!="none":                
                print('step3: slice time correction')
                step3(func_dir,subj_folder)
            else:
                for file in os.listdir(func_dir): # step 2: non-linear register to common space
                    if file.endswith(".nii.gz"):
                        subprocess.call(["gunzip",os.path.join(func_dir,file)])
                

            print('step4: motion correction')
            step4(func_dir,subj_folder,sub_ID)

            print('step5,6: acquiring correlation matrices')
	    
            step56(anat_dir,func_dir,subj_folder)
            #input('after step 56 ....')

 
def step1(anat_dir,file_):
    for file in os.listdir(anat_dir):# step 1: skull stripping
        if  "optiBET" not in file and file_ in file:
            print(os.path.join(anat_dir,file))
            subprocess.call(["/data1/software/optiBET.sh","-i",os.path.join(anat_dir,file)])

def step2(anat_dir,subj_folder):
    for file in os.listdir(anat_dir): # step 2: non-linear register to common space
        if file.endswith("optiBET_brain.nii.gz"):
            nonlinear_file = os.path.join(subj_folder,'code','nonlinear_setup')
	    f = open(nonlinear_file,"w")
            f.write("set inputlist(1) {/data1/software/bioimagesuite35/images/MNI_T1_1mm_stripped.nii.gz}\n")
            f.write("set inputlist(2) {"+os.path.join(anat_dir,file)+"}\n")
            f.write("set inputlist(3) {*ignore*}\nset inputlist(4) {*ignore*}\nset inputlist(5) {*ignore*}\nset outputsuffix {map.grd}\nset logsuffix \"results\"\nset cmdline \"bis_nonlinearbrainregister.tcl\"\n")
            f.close()
            subprocess.call(["bis_makebatch.tcl","-odir",anat_dir,"-setup",os.path.join(subj_folder,'code','nonlinear_setup'),"-makefile",os.path.join(subj_folder,'code','nonlinear.make')])
            subprocess.call(["make","-f",os.path.join(subj_folder,'code','nonlinear.make'),"-j","3"])

def step3(func_dir,subj_folder):
    for file in os.listdir(func_dir): # step 3: slice time correction
        if file.endswith(".nii.gz"):
	    slicetime_file = os.path.join(subj_folder,'code','slicetime_correction.csh')
            f = open(slicetime_file,"w")    
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
            subprocess.call(["sh","slicetime_correction.csh"])

def step4(func_dir,subj_folder,sub_ID):
    #for file in os.listdir(func_dir): # step 4: motion correction
        #if file.endswith(".nii") and not file.startswith('R_'):
    moco_file = os.path.join(subj_folder,'code','moco.csh')
    f = open(moco_file,"w")    
    f.write(matlab+" -nodesktop >motioncorrection.out <<EOF\n")
    f.write("path('/data1/software/spm12',path)\n")
    f.write("filter_expression=sprintf('^"+sub_ID+"_constable_stack4d_S0[0-9][0-9].nii$')\n")
    #f.write("filter_expression=\""+file+"$\"\n")
    f.write("parameter_dir='"+func_dir+"/realign/'\n")
    f.write("f=spm_select('FPList',deblank('"+func_dir+"'),filter_expression)\n")
    f.write("if ~isempty(f)\n")
    f.write("mrrc_motioncorrection_wrapper(f,"+str(use_old_flags)+",parameter_dir)\n");
    f.write("end\n")
    f.write("quit\n")
    f.write("EOF")
    f.close()
    subprocess.call(["sh",os.path.join(subj_folder,'code','moco.csh')])
    for file in os.listdir(func_dir):
	if file.endswith(".nii") and not file.startswith("p"):
	    subprocess.call(["bis_thresholdimage.tcl","-minth","-100000000000000","-maxth","1000000000000","-inp",os.path.join(func_dir,file)])
def step56(anat_dir,func_dir,subj_folder):
    mean_moco_files=[]
    for file in os.listdir(func_dir): # step 5: linear registeration to skull-stripped anatomical image
        if file.endswith("_thr.nii") and file.startswith("mean") and "LPS" not in file:
            mean_moco_files.append(file)
    mean_moco_files.sort(key=lambda x:x.split("_")[-2])
    print(mean_moco_files)
    if glob.glob(os.path.join(func_dir,'*LPS.nii')):
        mean_moco_file=mean_moco_files[int(math.floor(len(mean_moco_files)/2))].replace(".nii","_LPS.nii")
    else:
        mean_moco_file_tmp=mean_moco_files[int(math.floor(len(mean_moco_files)/2))]
        subprocess.call(["bis_newreorientimage.tcl","--inp",os.path.join(func_dir,mean_moco_file_tmp),"--out",os.path.join(func_dir,mean_moco_file_tmp.replace(".nii","_LPS.nii")),"--orientation LPS"])
        mean_moco_file=mean_moco_file_tmp.replace(".nii","_LPS.nii")
    #for file in os.listdir(func_dir): # step 5: linear registeration to skull-stripped anatomical image
       # if file.endswith(".hdr"):
       #     subprocess.call(["pxtonifti.tcl",os.path.join(func_dir,file)])
    #                        print('step 6: linear registeration to skull-stripped anatomical image %s'%file)
    for file_ in os.listdir(anat_dir):
        if file_.endswith("optiBET_brain.nii.gz") and "mask" not in file_ and "weight" not in file_ :
            anat_optiBET = file_
            subprocess.call(["epi_reg","--epi="+os.path.join(func_dir,mean_moco_file),"--t1="+os.path.join(anat_dir,file_),"--t1brain="+os.path.join(anat_dir,file_),"--out="+os.path.join(func_dir,file_).replace(".nii.gz","")+"_"+mean_moco_file.replace(".nii","")+"_fsl"])
    	for file_anat_ in os.listdir(func_dir):
            if file_anat_.endswith("_fsl.mat"):
                subprocess.call(["ConvertFromFSLMat.tcl",os.path.join(anat_dir,anat_optiBET),os.path.join(func_dir,mean_moco_file),os.path.join(func_dir,file_anat_),os.path.join(func_dir,anat_optiBET.replace(".nii.gz","")+"_"+mean_moco_file.replace(".nii","")+"_converted.matr"),"1"])
    for file in os.listdir(anat_dir):
        if file.endswith('_3rdpass.grd') and file.startswith('MNI_'):
            thirdpass_img = file
    for file in os.listdir(func_dir):
        if file.endswith('.matr') and 'mean' in file:
            mean_matr = file
    #                realign_mat = os.path.join('realign',file)
    num_runs=0 
    for file_run in os.listdir(func_dir):
        if file_run.endswith('_thr.nii') and file_run.startswith('R_'):
            num_runs=num_runs+1
    #for file in os.listdir(func_dir): # step 6: build connectivity matrix
    #    if not file.endswith('.nii') or not file.startswith('R_'):
    #    continue

    subjID=re.findall('p\w\d+',func_dir)[0]
    setup_file = os.path.join(subj_folder,'code','subj.xmlg')
    f = open(setup_file,"w")
    f.write("#BioImageSuite Study Description File v2\n")
    f.write("#-----------------------------------------------------\n")
    f.write("#Study Title\n")
    f.write(dataset_name+"\n")
    f.write("#Subject ID\n") 
    f.write(subjID+"\n")
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
    f.write('sess-1\n')
    f.write('#Session Description\n')
    f.write('DimensionalSuperData\n')
    f.write('#Number of Runs\n')
    f.write(''+str(num_runs)+'\n')
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
    run_id=1 
    moco_files=[]
    for file in os.listdir(func_dir): # step 5: linear registeration to skull-stripped anatomical image
        if file.endswith("_thr.nii") and file.startswith("R_"):
            moco_files.append(file)
    moco_files.sort(key=lambda x:x.split("_")[-2])
    
    for file_run in moco_files:
        if file_run.endswith('.nii') and file_run.startswith('R_'):
	    print(file_run)
            subprocess.call(["gzip",os.path.join(func_dir,file_run)])
            f.write('#Run '+str(run_id)+' (first line=4D Image, second line=Matrix with Motion Parameters)\n')
            f.write(os.path.join(func_dir,file_run)+".gz"+'\n')
            #print(re.findall("S\d+",file_run)+"_hiorder.mat")
            f.write(os.path.join(subj_folder,"func","realign","REALIGN_"+subjID+"_constable_stack4d_"+re.findall("S\d+",file_run)[0]+"_hiorder.mat" )+'\n')
            f.write(str(skip_frame_num)+'\n')
            run_id=run_id+1
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
    f.write('temporalsigma : '+str(temporalsigma)+'\n')
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
    subprocess.call(["bis_fmrisetup.tcl",setup_file,"matrix",os.path.join(func_dir,'result')])
main()                   
