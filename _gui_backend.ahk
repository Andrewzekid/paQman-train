﻿; (C) Copyright 2021, Bartlomiej Uliasz
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
; http://www.apache.org/licenses/LICENSE-2.0
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; Backend functions for GUI

StartTrainingCb(buttonCtrl, *) {
	global StatusUpdate

	buttonCtrl.Gui.Opt("+OwnDialogs")  ; Force the user to dismiss any created here dialogs before interacting with the main window.

	errors := ""
	for (key, value in WRONG_INPUT_MAP) {
		errors .= " • " value "`n"
	}
	if (errors) {
		NotAllowedBox("Please fix first following errors:`n" errors)
		return
	}

	StatusUpdate := ProgressStatusGui
	StatusUpdate("Training startup", buttonCtrl.Gui)

	outputDataExists := FileExist(OUTPUT_DIR "\unicharset")

	if (outputDataExists) {
		if (AUTO_CLEAN_OLD_DATA || YesNoConfirmation("The 'Training files output directory' (" OUTPUT_DIR ") already contains data. Do you want me to clean it? Otherwise any new Ground Truth content won't be used in this training.")) {
			DeleteModelData()
			outputDataExists := false
		}
	}

	if (!outputDataExists) {
		VerifyGtTxtFiles(buttonCtrl.Gui)
	}

	if (AUTO_SAVE) {
		StatusUpdate("Saving settings")
		SaveSettings(false)
	}

	try {
		trainingSuccess := StartTraining()
	} catch Error as e {
		StatusUpdate()	; closes status and re-enables main Gui
		ErrorBox(
			e.Message
			. "`n`nIf checkpoint files were created during the process you can use the 'Generate' button to generate '.traineddata' files."
			. ((DEBUG_MODE && e.HasProp("Extra")) ? "`n`n" e.Extra : "")
		)
	} else {
		SoundPlay "*-1"
		StatusUpdate()	; closes status and re-enables main Gui
		if (trainingSuccess) {
			UpdateModelFileInTessdata()
			if (SHUTDOWN_AFTER_TRAINING_COMPLETION) {
				Shutdown(9)
				TrayTip("Shutting down...")
				ExitApp
			}
			MsgBox("Training finished", PROGRAM_TITLE)
		} else {
			ErrorBox "Training ended with an error"
		}
	}

	return
}

; Returns false if there is no model to use.
UpdateModelFileInTessdata(generatedModelFile:="") {
	if (!generatedModelFile) {
		generatedModelFile := DATA_DIR "\" MODEL_NAME ".traineddata"
	}
	tessdataModelFile := TESSDATA "\" MODEL_NAME ".traineddata"
	shouldCopy := false
	if (!FileExist(generatedModelFile)) {
		ErrorBox("There is no newly generated model of name '" MODEL_NAME "' inside the " DATA_DIR " folder. Probably training didn't finish.")
		return false
	}
	if (!FileExist(tessdataModelFile)) {
		shouldCopy := AUTO_UPDATE_TESSDATA || SHUTDOWN_AFTER_TRAINING_COMPLETION || YesNoConfirmation("Your new model doesn't exist in your 'tessdata' folder. Do you want me to copy it so that you will be able to use it for recognition?")
		if (!shouldCopy) {
			return false
		}
	} else if (IsFileOlder(tessdataModelFile, generatedModelFile)) {
		shouldCopy := AUTO_UPDATE_TESSDATA || SHUTDOWN_AFTER_TRAINING_COMPLETION  || YesNoConfirmation("Do you want to update existing '" MODEL_NAME "' model in your 'tessdata' folder so that you will be able to use the new one for recognition?")
	}

	if (shouldCopy) {
		try {
			FileCopy(generatedModelFile, tessdataModelFile, true)
		} catch Error as e {
			if (YesNoConfirmation("Could not copy model file to '" tessdataModelFile "'. "
				. "Probably Administrator privileges are required for the target folder.`n"
				. "Do you want me to try again as an Administrator?")
			) {
				ExecuteCommand("copy /y `"" generatedModelFile "`" `"" tessdataModelFile "`"", 3, true)
				ExecuteCommand()
			} else {
				ErrorBox("Error copying new model file to '" tessdataModelFile "'.`n" e.Message)
				return false
			}
		}
	}
	return true
}

SaveSettings(showMessage) {
	mainGui.Opt("+OwnDialogs")  ; Force the user to dismiss any created here dialogs before interacting with the main window.

	for varableName in CONFIGURATION_VARIABLES_LIST {
		IniWrite(%varableName%, CONFIGURATION_FILE, "General", varableName)
	}

	if (showMessage) {
		MsgBox("Settings saved", PROGRAM_TITLE)
	}
}

LoadSettings(*) {
	for varableName in CONFIGURATION_VARIABLES_LIST {
		SetGlobal(varableName, IniRead(CONFIGURATION_FILE, "General", varableName, %varableName%))
	}
}

GetStartModelList() {
	nameList := FindAllFiles(TESSDATA "\*.traineddata")
	nameList := ArrayTransform(nameList, StrCutEnd, StrLen(".traineddata"))
	nameList := ArrayTransform(nameList, StrRCutTo, "\")
	nameList.InsertAt(1, "")
	return nameList
}

CleanModelData(*) {
	if (YesNoConfirmation("This action will permanently delete following files:`n"
		. (DELETE_MODEL_DIRECTORY ? "and all the content of the directory: " OUTPUT_DIR "`n" : "")
		. (DELETE_BOX_FILES ? GROUND_TRUTH_DIR "\*.box`n" : "")
		. (DELETE_LSTMF_FILES ? GROUND_TRUTH_DIR "\*.lstmf`n" : "")
		. "`nAre you sure?")
	) {
		if (DELETE_MODEL_DIRECTORY) {
			DeleteModelData()
		}
		if (DELETE_BOX_FILES) {
			DeleteBoxFiles()
		}
		if (DELETE_LSTMF_FILES) {
			DeleteLstmfFiles()
		}
		MsgBox("Cleaning finished")
	}
}

RemoveImageExtension(imagePath) {
	for fileExtension in SUPPORTED_IMAGE_FILES {
		if (StrEndsWith(imagePath, fileExtension)) {
			return StrCutEnd(imagePath, StrLen(fileExtension))
		}
	}
	return ""
}

GenerateTrainedData(*) {
	global mainGui

	mainGui.Opt("+OwnDialogs")  ; Force the user to dismiss any created here dialogs before interacting with the main window.

	if (FindAllFiles(OUTPUT_DIR "\checkpoints\" MODEL_NAME "*checkpoint").Length == 0) {
		ErrorBox("There are no checkpoint files yet for your selected model name. "
			. "Please run 'Start Training' first and then you will be able to use generated checkpoint files.")
		return
	}

	if (!CREATE_BEST_TRAINEDDATA && !CREATE_FAST_TRAINEDDATA) {
		ErrorBox("Please choose at least one of best and/or fast version option")
		return
	}

	checkpointFileList := FileSelect(
		"M3",
		OUTPUT_DIR "\checkpoints\",
		"Please select file(s) from which you want to to create 'traineddata'.",
		MODEL_NAME "*checkpoint")
	if (checkpointFileList.Length == 0) {
		return
	}
	if (CREATE_FAST_TRAINEDDATA) {
		MultipleCheckpointToTraineddata(checkpointFileList, true)
	}

	if (CREATE_BEST_TRAINEDDATA) {
		lastCreated := MultipleCheckpointToTraineddata(checkpointFileList, false)
		MsgBox("'.traineddata' model file" (checkpointFileList.Length > 1 ? "s" : "") " generated", PROGRAM_TITLE)
		if (checkpointFileList.Length == 1
			&& YesNoConfirmation("Do you want to update your Tessdata folder with the new best model file?")
			&& UpdateModelFileInTessdata(lastCreated)
		) {
			MsgBox("New model successfully updated in your Tessdata", PROGRAM_TITLE)
		}
	}
}

ExitGui(*) {
	ExitApp
}
