//
//  JSONDecoder+IJKLLPlayer.swift
//  IJKMediaFramework
//
//  Created by Xinzhe Wang on 12/15/18.
//  Copyright © 2018 bilibili. All rights reserved.
//

import Foundation

extension JSONDecoder {
    func decodeResponse<T: Decodable>(from response: DataResponse<Data>) -> Result<T> {
        guard response.error == nil else {
            print(response.error!)
            return .failure(response.error!)
        }
        
        guard let responseData = response.data else {
            print("didn't get any data from API")
            return .failure(IJKLLPlayerError.metaValidationFailed(reason: .dataNil))
        }
        
        do {
            let item = try decode(T.self, from: responseData)
            return .success(item)
        } catch {
            print("error trying to decode response")
            print(error)
            let err = IJKLLPlayerError.MetaValidationFailureReason.dataDecodeFailed(error: error)
            return .failure(IJKLLPlayerError.metaValidationFailed(reason: err))
        }
    }
}
