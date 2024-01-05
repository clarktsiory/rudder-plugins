/*
 *************************************************************************************
 * Copyright 2018 Normation SAS
 *************************************************************************************
 *
 * This file is part of Rudder.
 *
 * Rudder is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In accordance with the terms of section 7 (7. Additional Terms.) of
 * the GNU General Public License version 3, the copyright holders add
 * the following Additional permissions:
 * Notwithstanding to the terms of section 5 (5. Conveying Modified Source
 * Versions) and 6 (6. Conveying Non-Source Forms.) of the GNU General
 * Public License version 3, when you create a Related Module, this
 * Related Module is not considered as a part of the work and may be
 * distributed under the license agreement of your choice.
 * A "Related Module" means a set of sources files including their
 * documentation that, without modification of the Source Code, enables
 * supplementary functions or services in addition to those offered by
 * the Software.
 *
 * Rudder is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Rudder.  If not, see <http://www.gnu.org/licenses/>.

 *
 *************************************************************************************
 */

package com.normation.plugins.apiauthorizations

import com.normation.eventlog.ModificationId
import com.normation.rudder.api._
import com.normation.rudder.apidata.JsonApiAcl
import com.normation.rudder.rest._
import com.normation.rudder.rest.{UserApi => API}
import com.normation.rudder.rest.implicits.ToLiftResponseOne
import com.normation.rudder.rest.lift._
import com.normation.utils.DateFormaterService
import com.normation.utils.StringUuidGenerator
import io.scalaland.chimney.Transformer
import net.liftweb.http.LiftResponse
import net.liftweb.http.Req
import org.joda.time.DateTime
import zio.json._

class UserApi(
    readApi:        RoApiAccountRepository,
    writeApi:       WoApiAccountRepository,
    tokenGenerator: TokenGenerator,
    uuidGen:        StringUuidGenerator
) extends LiftApiModuleProvider[API] {
  api =>

  import UserApi._

  def schemas = API

  def getLiftEndpoints(): List[LiftApiModule] = {
    API.endpoints
      .map(e => {
        e match {
          case API.GetApiToken    => GetApiToken
          case API.CreateApiToken => CreateApiToken
          case API.DeleteApiToken => DeleteApiToken
          case API.UpdateApiToken => UpdateApiToken
        }
      })
      .toList
  }

  /*
   * By convention, an USER API token has the user login for identifier and name
   * (so that we enforce only one token by user - that could be change in the future
   * by only enforcing the name)
   */

  object GetApiToken extends LiftApiModule0 {
    val schema = API.GetApiToken
    def process0(version: ApiVersion, path: ApiPath, req: Req, params: DefaultParams, authzToken: AuthzToken): LiftResponse = {
      readApi
        .getById(ApiAccountId(authzToken.qc.actor.name))
        .map(RestAccountsResponse.fromRedacted(_))
        .chainError(s"Error when trying to get user '${authzToken.qc.actor.name}' API token")
        .toLiftResponseOne(params, schema, None)
    }
  }

  object CreateApiToken extends LiftApiModule0 {
    val schema = API.CreateApiToken
    def process0(version: ApiVersion, path: ApiPath, req: Req, params: DefaultParams, authzToken: AuthzToken): LiftResponse = {
      val now     = DateTime.now
      val secret  = ApiToken.generate_secret(tokenGenerator)
      val hash    = ApiToken.hash(secret)
      val account = ApiAccount(
        ApiAccountId(authzToken.qc.actor.name),
        ApiAccountKind.User,
        ApiAccountName(authzToken.qc.actor.name),
        ApiToken(hash),
        s"API token for user '${authzToken.qc.actor.name}'",
        isEnabled = true,
        now,
        now
      )

      writeApi
        .save(account, ModificationId(uuidGen.newUuid), authzToken.qc.actor)
        .map(RestAccountsResponse.fromUnredacted(_, secret))
        .chainError(s"Error when trying to save user '${authzToken.qc.actor.name}' API token")
        .toLiftResponseOne(params, schema, None)
    }
  }

  object DeleteApiToken extends LiftApiModule0 {
    val schema = API.DeleteApiToken
    def process0(version: ApiVersion, path: ApiPath, req: Req, params: DefaultParams, authzToken: AuthzToken): LiftResponse = {
      writeApi
        .delete(ApiAccountId(authzToken.qc.actor.name), ModificationId(uuidGen.newUuid), authzToken.qc.actor)
        .map(RestAccountIdResponse(_))
        .chainError(s"Error when trying to delete user '${authzToken.qc.actor.name}' API token")
        .toLiftResponseOne(params, schema, None)
    }
  }

  object UpdateApiToken extends LiftApiModule0 {
    val schema = API.UpdateApiToken
    def process0(version: ApiVersion, path: ApiPath, req: Req, params: DefaultParams, authzToken: AuthzToken): LiftResponse = {
      readApi
        .getById(ApiAccountId(authzToken.qc.actor.name))
        .map(RestAccountsResponse.fromRedacted(_))
        .chainError(s"Error when trying to get user '${authzToken.qc.actor.name}' API token")
        .toLiftResponseOne(params, schema, None)
    }
  }

}

object UserApi {

  /**
    * The value that will be displayed in the API response for the token.
    */
  final case class ClearTextToken(value: String) extends AnyVal

  object ClearTextToken {

    implicit val transformer: Transformer[ApiToken, ClearTextToken] = Transformer
      .define[ApiToken, ClearTextToken]
      .withFieldComputed(_.value, token => if (token.isHashed) "" else token.value)
      .buildTransformer

    implicit val encoder: JsonEncoder[ClearTextToken] = JsonEncoder[String].contramap(_.value)
  }

  final case class RestApiAccount(
      id:                              ApiAccountId,
      name:                            ApiAccountName,
      token:                           ClearTextToken,
      tokenGenerationDate:             DateTime,
      kind:                            ApiAccountType,
      description:                     String,
      creationDate:                    DateTime,
      @jsonField("enabled") isEnabled: Boolean,
      expirationDate:                  Option[String],
      expirationDateDefined:           Boolean,
      authorizationType:               Option[ApiAuthorizationKind],
      acl:                             Option[List[JsonApiAcl]]
  )

  object RestApiAccount extends UserJsonCodec {
    implicit class ApiAccountOps(val account: ApiAccount) extends AnyVal {
      import ApiAccountKind._
      import io.scalaland.chimney.syntax._
      def expirationDate: Option[String] = {
        account.kind match {
          case PublicApi(_, expirationDate) => expirationDate.map(DateFormaterService.getDisplayDateTimePicker)
          case User | System                => None
        }
      }

      def expirationDateDefined: Boolean = expirationDate.isDefined

      def authzType: Option[ApiAuthorizationKind] = {
        account.kind match {
          case PublicApi(authz, _) => Some(authz.kind)
          case User | System       => None
        }
      }

      def acl: Option[List[JsonApiAcl]] = {
        import ApiAuthorization._
        account.kind match {
          case PublicApi(authz, expirationDate) =>
            authz match {
              case None | RO | RW => Option.empty
              case ACL(acls)      => Some(acls.flatMap(x => x.actions.map(a => JsonApiAcl(x.path.value, a.name))))
            }
          case User | System                    => Option.empty
        }
      }

      /**
        * Always hides any hashed token, and displays any clear-text token
        */
      def toRest = account.transformInto[RestApiAccount]

      /**
        * Always displays the passed secret token
        */
      def toRestWithSecret(secret: ClearTextToken) = account.transformInto[RestApiAccount].copy(token = secret)
    }

    implicit val transformer: Transformer[ApiAccount, RestApiAccount] = Transformer
      .define[ApiAccount, RestApiAccount]
      .withFieldComputed(_.kind, _.kind.kind)
      .withFieldComputed(_.acl, _.acl)
      .withFieldComputed(_.expirationDate, _.expirationDate)
      .withFieldComputed(_.expirationDateDefined, _.expirationDateDefined)
      .withFieldComputed(
        _.authorizationType,
        _.authzType
      )
      .buildTransformer

    implicit val publicTokenEncoder: JsonEncoder[ApiToken] =
      JsonEncoder[String].contramap(_.value)

    implicit val encoder: JsonEncoder[RestApiAccount] = DeriveJsonEncoder.gen[RestApiAccount]
  }

  /**
    * The format of the API response is a list of accounts (it usually contains a single element or is empty)
    */
  final case class RestAccountsResponse private (
      accounts: List[RestApiAccount]
  )

  object RestAccountsResponse {
    import RestApiAccount._

    implicit val encoder: JsonEncoder[RestAccountsResponse] = DeriveJsonEncoder.gen[RestAccountsResponse]

    // The format of the API response is a list of accounts but contains only a single account, the secret is used to replace the token in the account
    private def apply(accounts: List[ApiAccount], secret: Option[ClearTextToken] = None): RestAccountsResponse = {
      new RestAccountsResponse(
        accounts.map(a => secret.map(a.toRestWithSecret(_)).getOrElse(a.toRest))
      )
    }

    def empty: RestAccountsResponse = RestAccountsResponse(Nil)

    /**
      * Displays the provided clear-text or hashed token for the api account 
      */
    def fromUnredacted(account: ApiAccount, secret: String): RestAccountsResponse = {
      apply(List(account), Some(ClearTextToken(secret)))
    }

    /**
      * Hides the hashed token and displays the clear-text token
      */
    def fromRedacted(account: Option[ApiAccount]): RestAccountsResponse = {
      // Don't send hashes in response
      apply(account.toList)
    }
  }

  final case class RestAccountId(id: ApiAccountId)
  final case class RestAccountIdResponse private (
      accounts: RestAccountId
  )

  object RestAccountIdResponse extends UserJsonCodec {
    implicit val accountIdResponseEncoder: JsonEncoder[RestAccountId]         = DeriveJsonEncoder.gen[RestAccountId]
    implicit val encoder:                  JsonEncoder[RestAccountIdResponse] = DeriveJsonEncoder.gen[RestAccountIdResponse]

    def apply(account: ApiAccountId): RestAccountIdResponse = new RestAccountIdResponse(RestAccountId(account))
  }

}
