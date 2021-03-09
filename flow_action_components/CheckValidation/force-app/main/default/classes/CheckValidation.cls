/** 
 *  Check Validation Flow Action
 * 
 *  Eric Smith - March 2021
 * 
 *  This class temporarily writes a record to an SObject to see if any  
 *  validation errors occurr and passes the errors back to the flow
 * 
 *  If there are multiple types of errors, only one type of error will be returned.
 *  If any Text fields are over their size limit, only those errors will be returned.
 *  If any Validation Rule fails, all Validation Rule failures will be returned.
 *  If any Required Fields are missing, only those errors will be returned.
 *  Fields over their size limit are handled first, followed by Validation Rules, followed by Required Fields.
 * 
 * 
**/ 

global inherited sharing class CheckValidation {

    // Attributes passed in from the Flow
    global class Requests {
    
        @InvocableVariable(label='Input Record')
        global SObject inputRecord;

        @InvocableVariable(label='Input Record Collection')
        global List<SObject> inputCollection;

        @InvocableVariable(Label='Record Identifier Field API Name')
        global String recordField;

        @InvocableVariable(Label='If no errors, commit inserted & updated records?')
        global Boolean isCommit;

    }

    // Attributes passed back to the Flow
    global class Results {

        @InvocableVariable 
        global Boolean isError;

        @InvocableVariable
        global String errorMessages;

        @InvocableVariable
        global String firstInsertedId;

        @InvocableVariable
        global List<String> insertedIdCollection;

    }

    // Standard Exception Handling
    global class InvocableActionException extends Exception {}

    // Expose this Action to the Flow
    @InvocableMethod
    global static List<Results> checkForValidationErrors(List<Requests> requestList) {

        // Prepare the response to send back to the Flow
        Results response = new Results();
        List<Results> responseWrapper = new List<Results>();

        // Bulkify proccessing of multiple requests
        for (Requests req : requestList) {

            // Set initial values
            Boolean errorFlag = false;
            String errorMessages = '';
            Integer nullAttributeCount = 0;
            String recordIdentifier = '';
            List<SObject> insertCollection = new List<SObject>();
            List<SObject> updateCollection = new List<SObject>();
            List<String> recordFieldIdentifierList = new List<String>();
            String firstInsertedId = '';
            List<String> insertedIdCollection = new List<String>();
            Boolean isFirst = true;
            Boolean invalidFieldName = false;

            // Get Input Value(s)
            SObject inputRecord = req.inputRecord;
            List<SObject> inputCollection = req.inputCollection;
            String recordField = req.recordField;
            Boolean isCommit = req.isCommit == null ? false : true;

            // Process input attributes
            if (inputRecord == null) {
                nullAttributeCount++; 
            }
            if (inputCollection == null) {
                nullAttributeCount++;
            }
            if (recordField == null) {
                recordField = 'Id';
            }

            // Handle Single Record
            if (inputRecord != null) {
                inputCollection = new List<SObject>();
                inputCollection.add(inputRecord);
            }  
            
            // Validate input attributes
            if (nullAttributeCount == 2) {
                throw new InvocableActionException('Flow Action Inputs Error: You need to pass a Record or Record Collection into this action.');
            }
            if (nullAttributeCount != 1) {
                throw new InvocableActionException('Flow Action Inputs Error: You must pass only one of Record or Record Collection into this action.');
            }
            try {
                String testFieldName = inputCollection[0].get(recordField).toString();     // This will error out if the recordField is not a valid field API name
            }
            catch (Exception e) {
                invalidFieldName = true;
            }

// BEGIN APEX ACTION PROCESSING LOGIC

            if (!errorFlag) {

                // Create Insert & Update Collections
                System.debug('Processing ' + inputCollection.size() + ' records');
                Integer recCounter = 0;
                String recIdentifier = '';
                for (SObject ir : inputCollection) {
                    if (recordField == 'Id' && ir.Id == null) {
                        recIdentifier = '<new record>';
                    } else {
                        recIdentifier = (!invalidFieldName) ? ir.get(recordField).toString() : '';
                    }
                    recordFieldIdentifierList.add(recIdentifier);
                    recCounter ++;
                    if (ir.Id == null) {
                        insertCollection.add(ir);
                    } else {
                        updateCollection.add(ir);
                    }
                }
                System.debug('Processing ' + insertCollection.size() + ' Insert records');
                System.debug('Processing ' + updateCollection.size() + ' Update records');

                // Set Save Point
                Savepoint sp = Database.setSavepoint();

                // Check for Insert Errors
                if (insertCollection.size() > 0) {
                    Database.SaveResult[] srListInsert = Database.insert(insertCollection, false);
                
                    recCounter = 0;
                    for (Database.SaveResult sr : srListInsert) {
                        recordIdentifier = recordFieldIdentifierList.get(recCounter);
                        recCounter ++;
                        if (sr.isSuccess()) {
                            if (isCommit) {
                                if (isFirst) {
                                    isFirst = false;
                                    firstInsertedId = sr.getId();
                                }
                                insertedIdCollection.add(sr.getId());
                            }
                            System.debug ('Insert Record Passed Validation: ' + sr.getId() + ' ' + recordIdentifier);
                        } else {
                            errorFlag = true;
                            for (Database.Error err : sr.getErrors()) {
                                errorMessages += 'New Record Error: ' + recordIdentifier + ' [' + err.getMessage() + ']\n';
                                System.debug ('New Record Validation Error: ' + err.getStatusCode() + ' - ' + err.getMessage());
                            }
                        }
                    }
                }

                // Check for Update Errors
                if (updateCollection.size() > 0) {
                    Database.SaveResult[] srListUpdate = Database.update(updateCollection, false);

                    recCounter = 0;
                    for (Database.SaveResult sr : srListUpdate) {
                        recordIdentifier = recordFieldIdentifierList.get(recCounter);
                        recCounter ++;            
                        if (sr.isSuccess()) {
                            System.debug ('Update Record Passed Validation: ' + sr.getId() + ' ' + recordIdentifier);
                        } else {
                            errorFlag = true;
                            for (Database.Error err : sr.getErrors()) {
                                errorMessages += recordIdentifier + ' [' + err.getMessage() + ']\n';
                                System.debug ('Record Update Validation Error: ' + err.getStatusCode() + ' - ' + err.getMessage());
                            }
                        }
                    }
                }
                
                // Revert Any Updates
                if (!isCommit || errorFlag) {
                    Database.rollback(sp);
                }

    // END APEX ACTION PROCESSING LOGIC

                // Set Output Values
                response.isError = errorFlag;
                response.errorMessages = errorMessages;
                if (!errorFlag) {
                    response.firstInsertedId = firstInsertedId;
                    response.insertedIdCollection = insertedIdCollection;
                }
                responseWrapper.add(response);

            }

        }

        // Return values back to the Flow
        return responseWrapper;
    }

}