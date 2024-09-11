module UserManagement exposing (processApiError, update)

import ApiCalls exposing (activateUser, addUser, disableUser, getRoleConf, getUsersConf, postReloadConf, updateUser, updateUserInfo)
import Browser
import DataTypes exposing (Model, Msg(..), PanelMode(..), StateInput(..), Username, mergeUserNewInfo, userProviders)
import Dict exposing (fromList)
import Http exposing (..)
import Init exposing (createErrorNotification, createSuccessNotification, defaultConfig, init, subscriptions)
import String exposing (isEmpty)
import Toasty
import View exposing (view)
import List
import List.FlatMap

main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CallApi call ->
            (model, call model)
        {--Api Calls message --}
        GetUserInfo result ->
            case result of
                Ok u ->
                    let
                        recordUser =
                            List.map (\x -> (x.login, x)) u.users
                        users = fromList recordUser
                        newPanelMode =
                            case model.ui.panelMode of
                                EditMode user ->
                                    case Dict.get user.login users of
                                        Just u_ ->
                                            EditMode u_
                                        Nothing ->
                                            Closed
                                _ ->
                                    Closed
                        ui = model.ui
                        newUI = {ui | panelMode = newPanelMode} 
                        newModel =
                            { model | roleListOverride = u.roleListOverride, users = users, ui = newUI, digest = u.digest, providers = (userProviders u.authenticationBackends), providersProperties = u.providersProperties}

                    in
                    ( newModel, getRoleConf model )

                Err err ->
                    processApiError err model
        GetRoleConf result ->
            case result of
                Ok roles ->
                    let
                        recordRole =
                            List.map (\x -> (x.id, x.rights)) roles
                        newModel =
                            { model | rolesConf = roles , roles = fromList recordRole}
                    in
                    ( newModel, Cmd.none )

                Err err ->
                    processApiError err model

        PostReloadUserInfo result ->
            case result of
                Ok _ ->
                    (model, getUsersConf model)

                Err err ->
                    processApiError err model

        SendReload ->
            (model, postReloadConf model)
                |> createSuccessNotification "User configuration file have been reloaded"

        ToastyMsg subMsg ->
            Toasty.update defaultConfig ToastyMsg subMsg model

        ActivePanelAddUser ->
            if model.ui.panelMode == AddMode then
                (resetFormPanel model Closed, Cmd.none)
            else
                (resetFormPanel model AddMode, Cmd.none)
        ActivePanelSettings user ->
            case model.ui.panelMode of
                EditMode u ->
                    if u.login == user.login then
                        (resetFormPanel model Closed, Cmd.none)
                    else
                        (resetFormPanel model (EditMode user), Cmd.none)
                _          ->
                    (resetFormPanel model (EditMode user), Cmd.none)

        DeactivatePanel ->
            (resetFormPanel model Closed, Cmd.none)

        AddUser result ->
             case result of
                 Ok username ->
                     (model, getUsersConf model )
                         |> createSuccessNotification (username ++ " have been added")
                 Err err ->
                     processApiError err model

        DeleteUser result ->
             case result of
                  Ok deletedUser ->
                       let
                           newModel = resetFormPanel model Closed
                       in
                           (newModel, getUsersConf model)
                           |> createSuccessNotification (deletedUser ++ " have been deleted")
                  Err err ->
                       processApiError err model

        UpdateUser result ->
             case result of
                  Ok username ->
                      (model, getUsersConf model)
                        |> createUserNotification username model

                  Err err ->
                       processApiError err model

        UpdateUserStatus result ->
             case result of
                  Ok username ->
                      (model, getUsersConf model)
                        |> createUserNotification username model

                  Err err ->
                       processApiError err model

        UpdateUserInfo result ->
             case result of
                  Ok _ ->
                      (model, getUsersConf model)
                        |> createSuccessNotification (model.userForm.login ++ " information has been modified")

                  Err err ->
                       processApiError err model

        AddRole r ->
            let
                userForm = model.userForm
            in
                ({model | userForm = {userForm | rolesToAddOnSave = r :: userForm.rolesToAddOnSave}}, Cmd.none)
        RemoveRole user provider r ->
            let
                -- remove role, and also authz that are associated to the role but not associated with any other remaining role
                newRoles = Dict.get provider user.providersInfo |> Maybe.map .roles |> Maybe.withDefault [] |> List.filter (\x -> r /= x) 
                newAuthz = 
                    -- keep authz if it is found in any authz of newRoles
                    -- keep authz if it's in custom authz of the user
                    let
                        allAuthz = Dict.toList model.roles |> List.FlatMap.flatMap (\(role, authz) -> if List.member role newRoles then authz else [])
                    in 
                        user.customRights ++ List.filter (\x ->
                            case model.roles |> Dict.get x of
                                Just _ -> True
                                Nothing -> 
                                    newRoles
                                    |> List.any (\y -> List.member y allAuthz)
                        ) user.authz
                newPanelMode = EditMode {user | authz = newAuthz, roles = newRoles}
                ui = model.ui
                newUI = {ui | panelMode = newPanelMode}
            in
            ({model | ui = newUI}, updateUser model user.login (DataTypes.UserAuth user.login "" (newAuthz ++ newRoles) model.userForm.isHashedPasswd))
        Notification subMsg ->
            Toasty.update defaultConfig Notification subMsg model

        Password newPassword ->
            let
                userForm = model.userForm
                newUserForm = { userForm | password = newPassword, isValidInput = ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        Login newLogin ->
            let
                userForm = model.userForm
                newUserForm = { userForm | login = newLogin, isValidInput = ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        NewUserInfoFieldKey key idx ->
            let
                userForm = model.userForm
                newUserInfoFields = List.indexedMap (\i (k, v) -> if i == idx then (key, v) else (k, v)) userForm.newUserInfoFields
                newUserForm = { userForm | newUserInfoFields = newUserInfoFields, isValidInput = if key == "" then InvalidNewUserInfoField else ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        NewUserInfoFieldValue value idx ->
            let
                userForm = model.userForm
                newUserInfoFields = List.indexedMap (\i (k, v) -> if i == idx then (k, value) else (k, v)) userForm.newUserInfoFields
                newUserForm = { userForm | newUserInfoFields = newUserInfoFields, isValidInput = if value == "" then InvalidNewUserInfoField else ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        RemoveNewUserInfoField idx ->
            let
                userForm = model.userForm
                newUserInfoFields = List.filterMap identity (List.indexedMap (\i (k, v) -> if i == idx then Nothing else Just (k, v)) userForm.newUserInfoFields)
                newUserForm = { userForm | newUserInfoFields = newUserInfoFields }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        ModifyUserInfoField key value ->
            let
                userForm = model.userForm
                userInfoForm = userForm.userInfoForm
                newUserInfoFields = Dict.insert key value userInfoForm.otherInfo
                newUserInfoForm = { userInfoForm | otherInfo = newUserInfoFields }
                newUserForm = { userForm | userInfoForm = newUserInfoForm }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        AddUserInfoField ->
            let
                userForm = model.userForm
                newUserForm = { userForm | newUserInfoFields = userForm.newUserInfoFields ++ [("", "")] }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        RemoveUserInfoField key ->
            let
                userForm = model.userForm
                userInfoForm = userForm.userInfoForm
                newUserInfoForm = { userInfoForm | otherInfo = Dict.remove key userInfoForm.otherInfo }
                newUserForm = { userForm | userInfoForm = newUserInfoForm }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        UserInfoName name ->
            let
                userForm = model.userForm
                userInfoForm = userForm.userInfoForm
                newUserInfoForm = { userInfoForm | name = name }
                newUserForm = { userForm | userInfoForm = newUserInfoForm, isValidInput = ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        UserInfoEmail email ->
            let
                userForm = model.userForm
                userInfoForm = userForm.userInfoForm
                newUserInfoForm = { userInfoForm | email = email }
                newUserForm = { userForm | userInfoForm = newUserInfoForm, isValidInput = ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        UserInfoFields fields ->
            let
                userForm = model.userForm
                userInfoForm = userForm.userInfoForm
                newUserInfoForm = { userInfoForm | otherInfo = fields }
                newUserForm = { userForm | userInfoForm = newUserInfoForm, isValidInput = ValidInputs }
            in
                ({model | userForm = newUserForm}, Cmd.none)
        SubmitUpdateUser u ->
            let
                newModel = resetFormPanel model model.ui.panelMode
            in
                (newModel, updateUser model u.login u)
        SubmitUserInfo ->
            let
                newModel = resetFormPanel model model.ui.panelMode
            in
                (newModel, updateUserInfo model model.userForm.login (mergeUserNewInfo model.userForm))
        SubmitNewUser u  ->
            if isEmpty u.login then
                let
                    userForm = model.userForm
                    newUserForm = { userForm | isValidInput = InvalidUsername }
                in
                    ({model | userForm = newUserForm}, Cmd.none)
            else
                let
                    newModel = resetFormPanel model Closed
                in
                    (newModel, addUser model (DataTypes.AddUserForm u model.userForm.password model.userForm.isHashedPasswd))
        ActivateUser username ->
            (model, activateUser model username)
        DisableUser username ->
            (model, disableUser model username)

        PreHashedPasswd bool ->
            let
                userForm = model.userForm
                newUserForm = {userForm | password = "", isHashedPasswd = bool}
            in
                ({model | userForm = newUserForm}, Cmd.none)
        AddPasswdAnyway ->
            if model.userForm.userForcePasswdInput then
                let
                    userForm = model.userForm
                    newUserForm = {userForm | password = "", userForcePasswdInput = False}
                in
                    ({model | userForm = newUserForm}, Cmd.none)
            else
                let
                    userForm = model.userForm
                    newUserForm = {userForm | userForcePasswdInput = True}
                in
                    ({model | userForm = newUserForm}, Cmd.none)
        OpenDeleteModal username ->
            let
                ui = model.ui
                newUI = {ui | openDeleteModal = True}
                userForm = model.userForm
                newUserForm = {userForm | login = username}
            in
                ({model | ui = newUI, userForm = newUserForm}, Cmd.none)
        CloseDeleteModal ->
            let
                ui = model.ui
                newUI = {ui | openDeleteModal = False}
                userForm = model.userForm
                newUserForm = {userForm | login = ""}
            in
                ({model | ui = newUI, userForm = newUserForm}, Cmd.none)

-- When a user with admin rights is updated, changes will not have effect now: session is kept until it expires
createUserNotification : Username -> Model -> (Model, Cmd Msg) -> (Model, Cmd Msg)
createUserNotification username model = 
    let
        hasAdminRights =
            model.users
                |> Dict.get username
                |> Maybe.map (.authz)
                |> Maybe.map (List.any (\auth -> "any_rights" == auth || String.startsWith "administration_" auth))
                |> Maybe.withDefault False
        message =
            if hasAdminRights then
                username ++ " has been modified, change will be taken into account on next login"
            else
                username ++ " has been modified"
    in
        createSuccessNotification message

processApiError : Error -> Model -> ( Model, Cmd Msg )
processApiError err model =
    let
        newModel =
            { model | digest = "", users = fromList []}
    in
    ( newModel, Cmd.none ) |> createErrorNotification "Error while trying to fetch settings." err

resetFormPanel : Model -> PanelMode -> Model
resetFormPanel model panelMode =
    let
        currentUserForm = model.userForm
        newLogin = 
            case panelMode of
                EditMode user -> user.login
                _ -> ""
        newFields = 
            case panelMode of
                EditMode user -> 
                    if user.login == currentUserForm.login then
                        mergeUserNewInfo currentUserForm
                    else
                        { name = user.name, email = user.email, otherInfo = user.otherInfo }
                _ -> { name = "", email = "", otherInfo = Dict.empty }
        newUI = { panelMode = panelMode, openDeleteModal = False }
        newUserInfoForm = 
            { name = newFields.name
            , email = newFields.email
            , otherInfo = newFields.otherInfo
            }
        newUserForm = 
            { login = newLogin
            , password = ""
            , isHashedPasswd = True
            , userForcePasswdInput = False
            , rolesToAddOnSave = []
            , newUserInfoFields = []
            , userInfoForm = newUserInfoForm
            , isValidInput = ValidInputs 
            }
    in
        { model | ui = newUI, userForm = newUserForm }