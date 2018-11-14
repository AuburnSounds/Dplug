//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/ipluginbase.h
//               public.sdk/source/main/pluginfactoryvst3.h
//               public.sdk/source/main/pluginfactoryvst3.cpp
// Created by  : Steinberg, 01/2004
// Description : Basic Plug-in Interfaces
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.ipluginbase;

import core.stdc.stdlib;
import core.stdc.string;

import dplug.vst3.funknown;
import dplug.vst3.ftypes;
import dplug.vst3.fstrdefs;

//------------------------------------------------------------------------
/**  Basic interface to a Plug-in component.
- [plug imp]
- initialize/terminate the Plug-in component

The host uses this interface to initialize and to terminate the Plug-in component.
The context that is passed to the initialize method contains any interface to the
host that the Plug-in will need to work. These interfaces can vary from category to category.
A list of supported host context interfaces should be included in the documentation
of a specific category. */
interface IPluginBase: IUnknown
{
public:
	/** The host passes a number of interfaces as context to initialize the Plug-in class.
		@note Extensive memory allocations etc. should be performed in this method rather than in the class' constructor!
		If the method does NOT return kResultOk, the object is released immediately. In this case terminate is not called! */
	tresult initialize(FUnknown* context);

	/** This function is called before the Plug-in is unloaded and can be used for
	    cleanups. You have to release all references to any host application interfaces. */
	tresult terminate();

	immutable __gshared FUID iid = FUID(IPluginBase_iid);
}

static immutable TUID IPluginBase_iid = INLINE_UID(0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625);


// Basic Information about the class factory of the Plug-in.

struct PFactoryInfo
{
nothrow:
@nogc:
    alias FactoryFlags = int;
	enum : FactoryFlags
	{
		kNoFlags					= 0,		///< Nothing
		kClassesDiscardable			= 1 << 0,	///< The number of exported classes can change each time the Module is loaded. If this flag is set, the host does not cache class information. This leads to a longer startup time because the host always has to load the Module to get the current class information.
		kLicenseCheck				= 1 << 1,	///< Class IDs of components are interpreted as Syncrosoft-License (LICENCE_UID). Loaded in a Steinberg host, the module will not be loaded when the license is not valid
		kComponentNonDiscardable	= 1 << 3,	///< Component won't be unloaded until process exit
		kUnicode                    = 1 << 4    ///< Components have entirely unicode encoded strings. (True for VST 3 Plug-ins so far)
	}

	enum
	{
		kURLSize = 256,
		kEmailSize = 128,
		kNameSize = 64
	}

	char8[kNameSize] vendor;		///< e.g. "Steinberg Media Technologies"
	char8[kURLSize] url;			///< e.g. "http://www.steinberg.de"
	char8[kEmailSize] email;		///< e.g. "info@steinberg.de"
	int32 flags;				///< (see above)

	this (const(char8)* _vendor, const(char8)* _url, const(char8)* _email, int32 _flags)
	{
		strncpy8 (vendor.ptr, _vendor, kNameSize);
		strncpy8 (url.ptr, _url, kURLSize);
		strncpy8 (email.ptr, _email, kEmailSize);
		flags = _flags;
		flags |= kUnicode;
	}
}

//------------------------------------------------------------------------
/**  Basic Information about a class provided by the Plug-in.
\ingroup pluginBase
*/
//------------------------------------------------------------------------
struct PClassInfo
{
nothrow:
@nogc:
	enum ClassCardinality
	{
		kManyInstances = 0x7FFFFFFF
	};

	enum
	{
		kCategorySize = 32,
		kNameSize = 64
	};

	TUID cid;                       ///< Class ID 16 Byte class GUID
	int32 cardinality;              ///< cardinality of the class, set to kManyInstances (see \ref ClassCardinality)
	char8[kCategorySize] category;  ///< class category, host uses this to categorize interfaces
	char8[kNameSize] name;          ///< class name, visible to the user

	this(const TUID _cid, int32 _cardinality, const(char8)* _category, const(char8)* _name)
	{
        cid[] = 0;
        cardinality = 0;
        category[] = '\0';
        name[] = '\0';
        cid = _cid;

		if (_category)
			strncpy8 (category.ptr, _category, kCategorySize);
		if (_name)
			strncpy8 (name.ptr, _name, kNameSize);
		cardinality = _cardinality;
	}
}


//------------------------------------------------------------------------
//  IPluginFactory interface declaration
//------------------------------------------------------------------------
/**	Class factory that any Plug-in defines for creating class instances.
\ingroup pluginBase
- [plug imp]

From the host's point of view a Plug-in module is a factory which can create
a certain kind of object(s). The interface IPluginFactory provides methods
to get information about the classes exported by the Plug-in and a
mechanism to create instances of these classes (that usually define the IPluginBase interface).

<b> An implementation is provided in public.sdk/source/common/pluginfactory.cpp </b>
\see GetPluginFactory
*/

interface IPluginFactory : IUnknown
{
public:
nothrow:
@nogc:
	/** Fill a PFactoryInfo structure with information about the Plug-in vendor. */
	tresult getFactoryInfo (PFactoryInfo* info);

	/** Returns the number of exported classes by this factory.
	If you are using the CPluginFactory implementation provided by the SDK, it returns the number of classes you registered with CPluginFactory::registerClass. */
	int32 countClasses ();

	/** Fill a PClassInfo structure with information about the class at the specified index. */
	tresult getClassInfo (int32 index, PClassInfo* info);

	/** Create a new class instance. */
	tresult createInstance (FIDString cid, FIDString _iid, void** obj);

    __gshared immutable FUID iid = FUID(IPluginFactory_iid);
}

static immutable TUID IPluginFactory_iid = INLINE_UID(0x7A4D811C, 0x52114A1F, 0xAED9D2EE, 0x0B43BF9F);


//  Version 2 of Basic Information about a class provided by the Plug-in.
struct PClassInfo2
{
	TUID cid;									///< Class ID 16 Byte class GUID
	int32 cardinality;							///< cardinality of the class, set to kManyInstances (see \ref ClassCardinality)
	char8[PClassInfo.kCategorySize] category;	///< class category, host uses this to categorize interfaces
	char8[PClassInfo.kNameSize] name;			///< class name, visible to the user

	enum {
		kVendorSize = 64,
		kVersionSize = 64,
		kSubCategoriesSize = 128
	};

	uint32 classFlags;				///< flags used for a specific category, must be defined where category is defined
	char8[kSubCategoriesSize] subCategories;	///< module specific subcategories, can be more than one, logically added by the \c OR operator
	char8[kVendorSize] vendor;		///< overwrite vendor information from factory info
	char8[kVersionSize] version_;	///< Version string (e.g. "1.0.0.512" with Major.Minor.Subversion.Build)
	char8[kVersionSize] sdkVersion;	///< SDK version used to build this class (e.g. "VST 3.0")

	this (const TUID _cid, int32 _cardinality, const(char8)* _category, const(char8)* _name,
		int32 _classFlags, const(char8)* _subCategories, const(char8)* _vendor, const(char8)* _version,
		const(char8)* _sdkVersion)
	{
        cardinality = 0;
        category[] = '\0';
        name[] = '\0';
        classFlags = 0;
        subCategories[] = '\0';
        vendor[] = '\0';
        version_[] = '\0';
        sdkVersion[] = '\0';
        cid = _cid;
		
		cardinality = _cardinality;
		if (_category)
			strncpy8 (category.ptr, _category, PClassInfo.kCategorySize);
		if (_name)
			strncpy8 (name.ptr, _name, PClassInfo.kNameSize);
		classFlags = cast(uint)(_classFlags);
		if (_subCategories)
			strncpy8 (subCategories.ptr, _subCategories, kSubCategoriesSize);
		if (_vendor)
			strncpy8 (vendor.ptr, _vendor, kVendorSize);
		if (_version)
			strncpy8 (version_.ptr, _version, kVersionSize);
		if (_sdkVersion)
			strncpy8 (sdkVersion.ptr, _sdkVersion, kVersionSize);
	}
}


interface IPluginFactory2 : IPluginFactory
{
public:
nothrow:
@nogc:
	/** Returns the class info (version 2) for a given index. */
	tresult getClassInfo2 (int32 index, PClassInfo2* info);

   __gshared immutable FUID iid = FUID(IPluginFactory2_iid);
}

static immutable TUID IPluginFactory2_iid = INLINE_UID(0x0007B650, 0xF24B4C0B, 0xA464EDB9, 0xF00B2ABB);


//------------------------------------------------------------------------
/** Unicode Version of Basic Information about a class provided by the Plug-in */
//------------------------------------------------------------------------
struct PClassInfoW
{
nothrow:
@nogc:
	TUID cid;							///< see \ref PClassInfo
	int32 cardinality;					///< see \ref PClassInfo
	char8[PClassInfo.kCategorySize] category;	///< see \ref PClassInfo
	char16[PClassInfo.kNameSize] name;	///< see \ref PClassInfo

	enum 
    {
		kVendorSize = 64,
		kVersionSize = 64,
		kSubCategoriesSize = 128
	}

	uint32 classFlags = 0;					///< flags used for a specific category, must be defined where category is defined
	char8[kSubCategoriesSize] subCategories;///< module specific subcategories, can be more than one, logically added by the \c OR operator
	char16[kVendorSize] vendor;			///< overwrite vendor information from factory info
	char16[kVersionSize] version_;		///< Version string (e.g. "1.0.0.512" with Major.Minor.Subversion.Build)
	char16[kVersionSize] sdkVersion;	///< SDK version used to build this class (e.g. "VST 3.0")

	this (const TUID _cid, int32 _cardinality, const(char8)* _category, const(char16)* _name,
		int32 _classFlags, const(char8)* _subCategories, const(char16)* _vendor, const(char16)* _version,
		const(char16)* _sdkVersion)
	{
        cid = _cid;
        cardinality = _cardinality;
        category[] = '\0';
        name[] = '\0';
        vendor[] = '\0';
        version_[] = '\0';
        sdkVersion[] = '\0';		
		if (_category)
			strncpy8 (category.ptr, _category, PClassInfo.kCategorySize);
		if (_name)
			strncpy16 (name.ptr, _name, PClassInfo.kNameSize);
		classFlags = cast(uint)(_classFlags);
		if (_subCategories)
			strncpy8 (subCategories.ptr, _subCategories, kSubCategoriesSize);
		if (_vendor)
			strncpy16 (vendor.ptr, _vendor, kVendorSize);
		if (_version)
			strncpy16 (version_.ptr, _version, kVersionSize);
		if (_sdkVersion)
			strncpy16 (sdkVersion.ptr, _sdkVersion, kVersionSize);
	}
    

	void fromAscii (ref const(PClassInfo2) ci2)
	{
		cid = ci2.cid;
		cardinality = ci2.cardinality;
		strncpy8 (category.ptr, ci2.category.ptr, PClassInfo.kCategorySize);
		str8ToStr16 (name.ptr, ci2.name.ptr, PClassInfo.kNameSize);
		classFlags = ci2.classFlags;
		strncpy8 (subCategories.ptr, ci2.subCategories.ptr, kSubCategoriesSize);
		str8ToStr16 (vendor.ptr, ci2.vendor.ptr, kVendorSize);
		str8ToStr16 (version_.ptr, ci2.version_.ptr, kVersionSize);
		str8ToStr16 (sdkVersion.ptr, ci2.sdkVersion.ptr, kVersionSize);
	}
}

interface IPluginFactory3 : IPluginFactory2
{
public:
nothrow:
@nogc:

	/** Returns the unicode class info for a given index. */
	tresult getClassInfoUnicode (int32 index, PClassInfoW* info);

	/** Receives information about host*/
	tresult setHostContext (FUnknown* context);

	__gshared immutable FUID iid = FUID(IPluginFactory3_iid);
}
static immutable TUID IPluginFactory3_iid = INLINE_UID(0x4555A2AB, 0xC1234E57, 0x9B122910, 0x36878931);


__gshared IPluginFactory gPluginFactory = null;

class CPluginFactory : IPluginFactory3
{
public:
nothrow:
@nogc:

    this(ref const PFactoryInfo info)
    {
        factoryInfo = info;
    }

	~this ()
    {
        if (gPluginFactory is this)
            gPluginFactory = null;

        if (classes)
        {
            free (classes);
            classes = null;
        }
    }

	/** Registers a Plug-in class with classInfo version 1, returns true for success. */
	bool registerClass (const(PClassInfo)* info,
						FUnknown function(void*) nothrow @nogc createFunc,
						void* context = null)
    {
        if (!info || !createFunc)
            return false;

        PClassInfo2 info2;
        memcpy (&info2, info, PClassInfo.sizeof);
        return registerClass(&info2, createFunc, context);
    }


	/** Registers a Plug-in class with classInfo version 2, returns true for success. */
	bool registerClass (const(PClassInfo2)* info,
						FUnknown function(void*) nothrow @nogc  createFunc,
						void* context = null)
    {        
        if (!info || !createFunc)
            return false;

        if (classCount >= maxClassCount)
        {
            if (!growClasses ())
                return false;
        }

        PClassEntry* entry = &classes[classCount];
        entry.info8 = *info;
        entry.info16.fromAscii (*info);
        entry.createFunc = createFunc;
        entry.context = context;
        entry.isUnicode = false;
        classCount++;
        return true;
    }

	/** Registers a Plug-in class with classInfo Unicode version, returns true for success. */
	bool registerClass (const(PClassInfoW)* info,
						FUnknown function(void*) nothrow @nogc createFunc,
						void* context = null)
    {
        if (!info || !createFunc)
            return false;

        if (classCount >= maxClassCount)
        {
            if (!growClasses ())
                return false;
        }

        PClassEntry* entry = &classes[classCount];
        entry.info16 = *info;
        entry.createFunc = createFunc;
        entry.context = context;
        entry.isUnicode = true;
        classCount++;
        return true;
    }


	/** Check if a class for a given classId is already registered. */
	bool isClassRegistered (ref const(FUID) cid)
    {
        for (int32 i = 0; i < classCount; i++)
        {
            if (iidEqual(cid.toTUID, classes[i].info16.cid))
                return true;
        }
        return false;
    }

    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IPluginFactory, IPluginFactory2, IPluginFactory3);

	mixin IMPLEMENT_REFCOUNT;

	//---from IPluginFactory------
	override tresult getFactoryInfo (PFactoryInfo* info)
    {
        if (info)
            memcpy (info, &factoryInfo, PFactoryInfo.sizeof);
        return kResultOk;
    }

	override int32 countClasses ()
    {
        return classCount;
    }

	override tresult getClassInfo (int32 index, PClassInfo* info)
    {
        if (info && (index >= 0 && index < classCount))
        {
            if (classes[index].isUnicode)
            {
                memset (info, 0, PClassInfo.sizeof);
                return kResultFalse;
            }

            memcpy (info, &classes[index].info8, PClassInfo.sizeof);
            return kResultOk;
        }
        return kInvalidArgument;
    }

	override tresult createInstance (FIDString cid, FIDString _iid, void** obj)
    {
        for (int32 i = 0; i < classCount; i++)
        {
            if (memcmp (classes[i].info16.cid.ptr, cid, TUID.sizeof ) == 0)
            {
                FUnknown instance = classes[i].createFunc (classes[i].context);
                if (instance)
                {
                    TUID* iid = cast(TUID*)_iid;
                    if (instance.queryInterface(*iid, obj) == kResultOk)
                    {
                        instance.release ();
                        return kResultOk;
                    }
                    else
                        instance.release ();
                }
                break;
            }
        }

        *obj = null;
        return kNoInterface;
    }

	//---from IPluginFactory2-----
	override tresult getClassInfo2 (int32 index, PClassInfo2* info)
    {
        if (info && (index >= 0 && index < classCount))
        {
            if (classes[index].isUnicode)
            {
                memset (info, 0, PClassInfo2.sizeof);
                return kResultFalse;
            }

            memcpy (info, &classes[index].info8, PClassInfo2.sizeof);
            return kResultOk;
        }
        return kInvalidArgument;
    }

	//---from IPluginFactory3-----
	override tresult getClassInfoUnicode (int32 index, PClassInfoW* info)
    {
        if (info && (index >= 0 && index < classCount))
        {
            memcpy (info, &classes[index].info16, PClassInfoW.sizeof);
            return kResultOk;
        }
        return kInvalidArgument;
    }

	override tresult setHostContext (FUnknown* context)
    {
        return kNotImplemented;
    }

protected:
	static struct PClassEntry
	{
		PClassInfo2 info8;
		PClassInfoW info16;

		FUnknown function(void*) nothrow @nogc createFunc;
		void* context;
		bool isUnicode;
	}

	PFactoryInfo factoryInfo;
	PClassEntry* classes = null;
	int32 classCount = 0;
	int32 maxClassCount = 0;

	bool growClasses()
    {
        static const int32 delta = 10;

        size_t size = (maxClassCount + delta) * PClassEntry.sizeof;
        void* memory = classes;

        if (!memory)
            memory = malloc (size);
        else
            memory = realloc (memory, size);

        if (!memory)
            return false;

        classes = cast(PClassEntry*)memory;
        maxClassCount += delta;
        return true;
    }
}

