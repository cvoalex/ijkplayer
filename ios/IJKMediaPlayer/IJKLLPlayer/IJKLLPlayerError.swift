//
//  IJKLLPlayerError.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/15/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

enum IJKLLPlayerError: Error {
    
    enum MetaValidationFailureReason {
        case dataNil
        case dataDecodeFailed(error: Error)
    }
    
    enum ResponseSerializationFailureReason {
        case inputDataNil
        case inputDataNilOrZeroLength
        case inputFileNil
        case inputFileReadFailed(at: URL)
        case stringSerializationFailed(encoding: String.Encoding)
        case jsonSerializationFailed(error: Error)
        case propertyListSerializationFailed(error: Error)
    }
    
    case metaValidationFailed(reason: MetaValidationFailureReason)
    case responseSerializationFailed(reason: ResponseSerializationFailureReason)
}
