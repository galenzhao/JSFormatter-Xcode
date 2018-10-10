//
//  JSFormatter+helper.m
//  JSFormatter
//
//  Created by zx on 6/13/15.
//  Copyright (c) 2015 zztx. All rights reserved.
//

#import "JSFormatter+helper.h"
#import <objc/runtime.h>

static const char *getPropertyType(objc_property_t property) {
    const char *attributes = property_getAttributes(property);
    char buffer[1 + strlen(attributes)];
    strcpy(buffer, attributes);
    char *state = buffer, *attribute;
    while ((attribute = strsep(&state, ",")) != NULL) {
        if (attribute[0] == 'T') {
            if (strlen(attribute) <= 4) {
                break;
            }
            return (const char *)[[NSData dataWithBytes:(attribute + 3) length:strlen(attribute) - 4] bytes];
        }
    }
    return "@";
}

/**
 *  Gets a list of all methods on a class (or metaclass)
 *  and dumps some properties of each
 *
 *  @param clz the class or metaclass to investigate
 */
void DumpObjcMethods(Class clz) {
    
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(clz, &methodCount);
    
    printf("Found %d methods on '%s'\n", methodCount, class_getName(clz));
    
    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        
        printf("\t'%s' has method named '%s' of encoding '%s'\n",
               class_getName(clz),
               sel_getName(method_getName(method)),
               method_getTypeEncoding(method));
        
        /**
         *  Or do whatever you need here...
         */
    }
    
    free(methods);
}

@implementation JSFormatter (helper)

+ (IDEWorkspaceDocument *)currentWorkspaceDocument
{
    NSWindowController *currentWindowController = [[NSApp keyWindow] windowController];
    id document = [currentWindowController document];
    
    if (currentWindowController && [document isKindOfClass:NSClassFromString(@"IDEWorkspaceDocument")]) {
        return (IDEWorkspaceDocument *)document;
    }
    return nil;
}

+ (NSTextView *)currentSourceCodeTextView
{
    if ([[self currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeEditor")]) {
        IDESourceCodeEditor *editor = [self currentEditor];
        return editor.textView;
    }
    
    if ([[self currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeComparisonEditor")]) {
        IDESourceCodeComparisonEditor *editor = [self currentEditor];
        return editor.keyTextView;
    }
    
    return nil;
}

+ (id)currentEditor
{
    NSWindowController *currentWindowController = [[NSApp keyWindow] windowController];
    NSLog(@"%s %d, %@", __func__, __LINE__, currentWindowController);
    //IDEWorkspaceWindowController
    //IDEWorkspaceWindowController
    if ([currentWindowController isKindOfClass:NSClassFromString(@"IDEWorkspaceWindowController")]) {
        IDEWorkspaceWindowController *workspaceController = (IDEWorkspaceWindowController *)currentWindowController;
        IDEEditorArea *editorArea = [workspaceController editorArea];
        IDEEditorContext *editorContext = [editorArea lastActiveEditorContext];
        NSLog(@"%@\n%@\n%@", editorArea, editorContext, editorContext.editor);
        return [editorContext editor];
    }
    return nil;
}

+ (void)myMethod:(Class)c {
    unsigned int outCount, i;
    objc_property_t *properties = class_copyPropertyList(c, &outCount);
    NSLog(@"class method: %@", c);
    for(i = 0; i < outCount; i++) {
        objc_property_t property = properties[i];
        const char *propName = property_getName(property);
        if(propName) {
            const char *propType = getPropertyType(property);
            NSString *propertyName = [NSString stringWithCString:propName
                                                        encoding:[NSString defaultCStringEncoding]];
            NSString *propertyType = [NSString stringWithCString:propType
                                                        encoding:[NSString defaultCStringEncoding]];
//            ...
            NSLog(@"%@: %@", propertyType, propertyName);
        }
    }
    free(properties);
}

+ (NSString *)formattedCodeOfString:(NSString *)string pathExtension:(NSString *)pathExtension {
    NSString *path = @"/tmp/out.tmp.$$";
    [string writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    //1
    NSTask *task = [[NSTask alloc] init];
    
    //2
    task.launchPath = @"/usr/local/bin/node";
    
    //init output pipe
    NSPipe *outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    
    //3
    if ([pathExtension isEqualToString:@"json"]) {
        pathExtension = @"js";
    }
    NSString *command = [NSString stringWithFormat:@"/usr/local/bin/%@-beautify",pathExtension];
    task.arguments = @[command, path];
    
    //4
    [task launch];
    
    //5
    [task waitUntilExit];
    
    NSFileHandle *read = [outputPipe fileHandleForReading];
    NSData *dataRead = [read readDataToEndOfFile];
    NSString *stringRead = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
    NSLog(@"output: %@", stringRead);
    
    
    return stringRead;
}


+ (IDESourceCodeDocument *)currentSourceCodeDocument
{
    //IDESourceEditor.SourceCodeEditor
    NSString *cname = NSStringFromClass([[[self class] currentEditor] class]);
    NSLog(@"editor class name:%@", cname);
    
    if ([@"IDESourceEditor.SourceCodeEditor" isEqualToString:cname]) {
        IDESourceCodeEditor *editor = [[self class] currentEditor];
        NSLog(@"%s, %@", __func__, editor);
        [[self class] myMethod:[editor class]];
        //IDESourceEditorView
        //currentSelectedDocumentLocations
        NSLog(@"%@", editor.textView);
        NSLog(@"%@", editor.currentSelectedDocumentLocations);
        
        [[self class] myMethod:[editor.currentSelectedDocumentLocations class]];
//        DumpObjcMethods([editor class]);
//        DumpObjcMethods([editor.currentSelectedDocumentLocations class]);
        NSString *desc = [editor.currentSelectedDocumentLocations description];
        NSArray *part = [desc componentsSeparatedByString:@","];
        NSLog(@"%@", part);
        NSString *path = [part[1] stringByReplacingOccurrencesOfString:@" documentURL:file://" withString:@""];
        
        NSURL *url = [NSURL fileURLWithPath:path];
        NSArray *types = @[@"js",@"html",@"css",@"json",@"htm"];
        if ([types indexOfObject:url.pathExtension] == NSNotFound) {
            //not support other file types
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Only support js\\html\\htm\\css\\json now"];
            [alert runModal];
            return NO;
        }
        
        //string
        NSString *originalString = editor.textView.string;
        NSString *formattedCode = [self formattedCodeOfString:originalString pathExtension:@"js"];
        
        NSError *error = nil;
        [formattedCode writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
////            editor.textView.string = formattedCode;
//            SEL selector = NSSelectorFromString(@"selectedTextRange");
//            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
//                                        [[editor.textView class] instanceMethodSignatureForSelector:selector]];
//            [invocation setSelector:selector];
//            [invocation setTarget:editor.textView];
//            [invocation invoke];
//
//            NSRange r = NSMakeRange(0, 0);
//            [invocation getReturnValue:&r];
//
//            // insertText:replacementRange:
//            [editor.textView insertText:formattedCode replacementRange:r];
//
//        });
        
        return nil;
        //return editor.sourceCodeDocument;
    }
    
    if ([[[self class] currentEditor] isKindOfClass:NSClassFromString(@"IDESourceCodeComparisonEditor")]) {
        IDESourceCodeComparisonEditor *editor = [[self class] currentEditor];
        
        if ([[editor primaryDocument] isKindOfClass:NSClassFromString(@"IDESourceCodeDocument")]) {
            IDESourceCodeDocument *document = (IDESourceCodeDocument *)editor.primaryDocument;
            NSLog(@"%s, %@", __func__, document);

            return document;
        }
    }
    NSLog(@"%s, %@", __func__, @"");

    return nil;
}

+ (void)formatDocument:(IDESourceCodeDocument *)document withError:(NSError **)outError
{
    NSTextView *textView = [self currentSourceCodeTextView];
    
    DVTSourceTextStorage *textStorage = [document textStorage];
    
    // We try to restore the original cursor position after the uncrustification. We compute a percentage value
    // expressing the actual selected line compared to the total number of lines of the document. After the uncrustification,
    // we restore the position taking into account the modified number of lines of the document.
    
    NSRange originalCharacterRange = [textView selectedRange];
    NSRange originalLineRange = [textStorage lineRangeForCharacterRange:originalCharacterRange];
    NSRange originalDocumentLineRange = [textStorage lineRangeForCharacterRange:NSMakeRange(0, textStorage.string.length)];
    
    CGFloat verticalRelativePosition = (CGFloat)originalLineRange.location / (CGFloat)originalDocumentLineRange.length;
    
    IDEWorkspace *currentWorkspace = [self currentWorkspaceDocument].workspace;
    
    [self formatCodeOfDocument:document inWorkspace:currentWorkspace error:outError];
    
    NSRange newDocumentLineRange = [textStorage lineRangeForCharacterRange:NSMakeRange(0, textStorage.string.length)];
    NSUInteger restoredLine = roundf(verticalRelativePosition * (CGFloat)newDocumentLineRange.length);
    
    NSRange newCharacterRange = NSMakeRange(0, 0);
    
    newCharacterRange = [textStorage characterRangeForLineRange:NSMakeRange(restoredLine, 0)];
    
    // If the selected line didn't change, we try to restore the initial cursor position.
    
    if (originalLineRange.location == restoredLine && NSMaxRange(originalCharacterRange) < textStorage.string.length) {
        newCharacterRange = originalCharacterRange;
    }
    
    if (newCharacterRange.location < textStorage.string.length) {
        [[self currentSourceCodeTextView] setSelectedRanges:@[[NSValue valueWithRange:newCharacterRange]]];
        [textView scrollRangeToVisible:newCharacterRange];
    }
}

+ (BOOL)formatCodeOfDocument:(IDESourceCodeDocument *)document inWorkspace:(IDEWorkspace *)workspace error:(NSError **)outError
{
    return YES;
//    NSError *error = nil;
//    
//    DVTSourceTextStorage *textStorage = [document textStorage];
//    
//    NSString *originalString = [NSString stringWithString:textStorage.string];
//    
//    if (textStorage.string.length > 0) {
//        CFOFormatter *formatter = [[self class] formatterForString:textStorage.string presentedURL:document.fileURL error:&error];
//        NSString *formattedCode = [formatter stringByFormattingInputWithError:&error];
//        
//        if (formattedCode) {
//            [textStorage beginEditing];
//            
//            if (![formattedCode isEqualToString:textStorage.string]) {
//                [textStorage replaceCharactersInRange:NSMakeRange(0, textStorage.string.length) withString:formattedCode withUndoManager:[document undoManager]];
//            }
//            [self normalizeCodeAtRange:NSMakeRange(0, textStorage.string.length) document:document];
//            [textStorage endEditing];
//        }
//    }
//    
//    if (error && outError) {
//        *outError = error;
//    }
//    
//    BOOL codeHasChanged = (originalString && ![originalString isEqualToString:textStorage.string]);
//    return codeHasChanged;
}



@end
