'===============Check for Existing User Sub================================

CheckUser:	   If NUA = 5 then 'there are no User entries in the table
				 Return
			   EndIf
			  
			   ENDline = NUA		 'Set Endline to first empty spot		  
			  'If there are exisiting keys then check to see if Employee # exists
			  	  	  	Index2 = 5 		' Start search in first memory spot		  			 				
NextUser:  				For Index = 0 to 2	  'Cycle through employee #
						 Flag = 0	   'If the User exists then we will set the Flag to 1 	  	 	  
						B1 = EREAD Index2 + Index  
				  		If NOT B1 = CE[Index]then 'If any digit does not match then
				  			 Break 	  				   'Break out of For/Next loop
				  		Else
							Flag = 1 ' The digit Matches
						ENDIF
					Next Index   'Look at the next digit
				  	If Flag = 1 then Goto EmployeeExists		
			  Index2 = Index2 + 8
			  If Index2 = Endline then Return
			  B1 = "C"
			  Goto NextUser

EmployeeExists:		 Gosub BadSound
					CLS
					PRINT AT 1,1,"User Exists!"
					PRINT AT 2,1, "Delete User?"
					Print AT 1,17,"(1) = Yes"
					Print At 2,17,"(2) = No"
					GOSUB GetKey
					Select Key
						Case 2 'Choice was not to delete User
						   		GoTo MainMenu  'Exit adding user
						Case 1 'Yes, delete this user. We will add a new key for him						 
							 Goto DeleteUser
						Case Else 'Key was not 1 or 2"
							 	Goto EmployeeExists
					EndSelect		

DeleteUser:			If Index2  = EndLine - 8  then 'If the Employee# is the last one in the table then
						NUA = NUA - 8 'remove last entry
						EWRITE 255, [NUA]		  'Enter new next user address into pointer spot
						Return
					Else
MoveSpot:				NUA = NUA - 8  
					 	EWRITE 255, [NUA]	  'Enter new next user address into pointer spot
					 
					 	For Index = 0 to 7
					 		B1 = EREAD NUA + Index
					 		EWRITE Index2 + Index, [B1]
					 	Next
					 	B1 = "C"
					 	Return	  
					ENDIF
							  	  		   
'...................End of CheckUser routine...............................